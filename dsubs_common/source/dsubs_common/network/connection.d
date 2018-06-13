module dsubs_common.network.connection;

import std.algorithm;
import std.exception;
import std.concurrency;
import std.conv: to;
import std.socket;
import core.atomic;
import core.thread;
import core.time: Duration, seconds, msecs;

import dsubs_common.event;
import dsubs_common.api.constants;
import dsubs_common.api.utils: ProtocolException;
import dsubs_common.utils;


/// Exception thrown from TCP-related code.
class ConnectionException: Exception
{
	mixin ExceptionConstructors;
}

/// Messages that socket writer thread accepts
private enum WriterMsg: byte
{
	TERMINATE
}

private string generateRandomString()
{
	import std.ascii, std.base64, std.conv, std.random, std.range, std.array;
	auto rndNums = rndGen.takeExactly(12).map!(i => cast(ubyte)(i % 256))();
	auto result = appender!string();
	Base64.encode(rndNums, result);
	rndGen.popFrontExactly(10);
	return result.data.filter!isAlphaNum.to!string;
}


/// Duplex disciplined connection with timeouts. Each connection is managed by two
/// threads - reader and writer.
class ProtocolConnection(alias Protocol)
{
	protected
	{
		Socket m_sock;
		Address m_remoteAddr;
		Thread m_readerThread;
		Tid m_writerThread;
		shared bool m_closed, m_started;
		string m_conId;

		/// Connection implements some dsubs protocol. Each protocol
		/// message begins with an int wich signifies message type.
		/// Message body in raw form is passed to the delegate.
		/// Handlers are run in the m_readerThread thread.
		void delegate(ubyte[] msgBody)[] m_handlers;
	}

	/// Create connection by adopting the socket.
	this(Socket sock)
	{
		assert(sock);
		m_sock = sock;
		sock.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, seconds(10));
		sock.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, seconds(10));
		m_remoteAddr = sock.remoteAddress();
		m_conId = "[" ~ generateRandomString() ~ "]";
		m_handlers.length = Protocol.msgTypeCount;
	}

	final void clearHandlers()
	{
		for (size_t i = 0; i < m_handlers.length; i++)
			m_handlers[i] = null;
	}

	/// Connection identifier for logging.
	@property string conId() const
	{
		return m_conId;
	}

	final @property bool isOpen() const
	{
		return !atomicLoad(m_closed) && m_started;
	}

	/// Start serving the protocol connection (starts reader and writer)
	/// tasks.
	final void start()
	{
		m_readerThread = new Thread(&readProc).start();
		m_writerThread = spawn(cast(shared void delegate()) &writerProc);
		m_started = true;
	}

	final void sendMessage(MsgT)(immutable MsgT msg)
	{
		sendBytes(Protocol.marshal(msg));
	}

	/// send asynchroniously (caller thread does not block)
	private void sendBytes(immutable(ubyte)[] data)
	{
		send!(immutable(ubyte)[])(m_writerThread, data);
	}

	/// send raw bytes to the peer
	private void sendBytesSync(const(ubyte)[] msgBody)
	{
		auto sent = m_sock.send(msgBody);
		enforce!ConnectionException(sent == msgBody.length, "Error during send");
	}

	/// Set handler for protocol message of type MsgT. Can be only called once.
	final void setHandler(MsgT)(void delegate(MsgT msg) handler)
	{
		assert(handler);
		if (m_handlers[MsgT.g_marshIdx])
			throw new Exception("Handler already set");
		m_handlers[MsgT.g_marshIdx] =
			(ubyte[] msgBody) { handler(Protocol.demarshal!MsgT(msgBody)); };
	}

	/// synchronous close
	final void close()
	{
		assert(m_started);
		// connection will be closed once
		if (!cas(&m_closed, false, true))
			return;
		info(conId ~ " Closing connection to ", m_remoteAddr);
		send!WriterMsg(m_writerThread, WriterMsg.TERMINATE);
		doClose();
	}

	private void doClose()
	{
		m_sock.shutdown(SocketShutdown.BOTH);
		m_sock.close();
		onClose(this);
	}

	/// Fired when connection and the socket were declared closed
	Event!(void delegate(typeof(this))) onClose;

	// first int - message type, second - body size.
	private int[2] recvHeader()
	{
		int[2] header;
		auto received = m_sock.receive(header);
		enforce!ConnectionException(received == 8, "Error during receive");
		enforce!ProtocolException(header[0] >= -1 &&
			header[0] < m_handlers.length, "Unknown message " ~ header[0].to!string);
		enforce!ProtocolException(header[1] >= 0 &&
			header[1] <= MAX_MSG_SIZE, "Message length invalid");
		if (header[0] >= 0)
			trace(conId ~ " received message header ",
				Protocol.msgTypeNames[header[0]], " ", header[1]);
		else
			trace(conId ~ " received message header ", header);
		return header;
	}

	private ubyte[] recvBody(int size)
	{
		ubyte[] res = new ubyte[size];
		auto received = m_sock.receive(res);
		enforce!ConnectionException(received == size, "Error during receive");
		return res;
	}

	private void readProc()
	{
		try
		{
			while (true)
			{
				int[2] header = recvHeader();
				if (header[0] == -1)
				{
					// Keel-alive message
					continue;
				}
				void delegate(ubyte[]) handler = m_handlers[header[0]];
				if (handler)
					handler(recvBody(header[1]));
				else
					throw new ProtocolException("Unacceptable message " ~ header[0].to!string);
			}
		}
		catch (Exception e)
		{
			error(conId ~ " Exception caught in reader thread: ", e.msg);
			close();
		}
		catch (Throwable e)
		{
			error(conId ~ " Throwable caught in reader thread: ", e.toString());
			throw e;
		}
	}

	private void writerProc()
	{
		try
		{
			bool exitFlag;
			while(!exitFlag)
			{
				try
				{
					bool timedOut = !receiveTimeout(seconds(5),
						(immutable(ubyte)[] msgBody)
						{
							sendBytesSync(msgBody);
						},
						(WriterMsg msg)
						{
							if (msg == WriterMsg.TERMINATE)
								exitFlag = true;
						});
					if (timedOut)
					{
						// send keep-alive message
						ubyte[8] ka;
						*(cast(int*)ka.ptr) = int(-1);
						sendBytesSync(ka[]);
					}
				}
				catch (OwnerTerminated otex)
				{
					trace(conId ~ " swallowing OwnerTerminated");
				}
			}
		}
		catch (Throwable e)
		{
			error(conId ~ " Throwable caught in writer thread: ", e.msg);
			close();
		}
	}
}


unittest
{
	import dsubs_common.api.protocols.backend;
	import dsubs_common.api.protocol: BackendProtocol;

	auto thread1 = new Thread(()
	{
		Socket listenSock = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.IP);
		scope(exit) listenSock.close();
		// https://serverfault.com/a/329848
		listenSock.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
		listenSock.bind(new InternetAddress("127.0.0.1", 25511));
		listenSock.listen(16);
		ProtocolConnection!BackendProtocol client, server;
		auto thread2 = new Thread(()
		{
			Socket clientSock = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.IP);
			clientSock.connect(new InternetAddress("127.0.0.1", 25511));
			client = new ProtocolConnection!BackendProtocol(clientSock);
			client.m_conId = "[client]";
			client.start();
		}).start();
		Socket serverSock = listenSock.accept();
		server = new ProtocolConnection!BackendProtocol(serverSock);
		server.m_conId = "[server]";
		bool msgReceived;
		server.setHandler((LoginReq req)
			{
				assert(req.username == "test");
				msgReceived = true;
			});
		server.start();
		thread2.join();
		client.sendMessage(immutable LoginReq("test"));
		Thread.sleep(msecs(100));
		assert(msgReceived);
		// some unknowm message
		immutable(ubyte)[] fakeData = [0x70, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
		client.sendBytes(fakeData);
		Thread.sleep(msecs(100));
		assert(!server.isOpen);
		assert(!client.isOpen);
	}).start();
	thread1.join();
}