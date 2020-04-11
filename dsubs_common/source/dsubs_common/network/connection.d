module dsubs_common.network.connection;

import std.algorithm;
import std.exception;
import std.concurrency;
import std.conv: to;
import std.socket;
import std.range: retro;

import core.stdc.errno;
import core.atomic;
import core.thread;
import core.time: Duration, seconds, msecs;

import dsubs_common.event;
import dsubs_common.api.constants;
import dsubs_common.api.utils: ProtocolException;
import dsubs_common.api.encryption;
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

/// parse url of the type  IP:port
InternetAddress parseUrl(string url)
{
	auto lastColIdx = url[].retro.countUntil(':');
	if (lastColIdx < 0)
		throw new Exception("must specify TCP port");
	trace(url, ' ', lastColIdx);
	return new InternetAddress(url[0..$-lastColIdx-1], url[$-lastColIdx..$].to!ushort);
}

private string generateRandomString()
{
	import std.ascii, std.base64, std.conv, std.random, std.range, std.array;
	auto rndNums = rndGen.takeExactly(7).map!(i => cast(ubyte)(i % 256))();
	auto result = appender!string();
	Base64.encode(rndNums, result);
	rndGen.popFrontExactly(7);
	return result.data.filter!isAlphaNum.to!string;
}

/// register all methods of "this" ProtocolConnection that start with "h_" as message handlers.
void mixinHandlers(T)(T that)
{
	foreach (memberName; __traits(allMembers, T))
	{
		static if (memberName.length > 2 && memberName[0..2] == "h_" &&
			is(typeof(__traits(getMember, that, memberName)) == function))
		{
			that.setHandler(&__traits(getMember, that, memberName));
		}
	}
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
		shared int m_writeQueueSize = 0;
		string m_conId;

		/// Connection implements some dsubs protocol. Each protocol
		/// message begins with an int wich signifies message type.
		/// Message body in raw form is passed to the delegate.
		/// Handlers are run in the m_readerThread thread.
		void delegate(ubyte[] msgBody)[] m_handlers;
	}

	alias MessageProtocol = Protocol;

	/// Create connection by adopting the socket.
	this(Socket sock)
	{
		assert(sock);
		m_sock = sock;
		sock.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, seconds(30));
		sock.setOption(SocketOptionLevel.SOCKET, SocketOption.SNDTIMEO, seconds(30));
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
		m_writerThread = spawn(cast(shared void delegate()) &writerProc);
		m_readerThread = new Thread(&readProc).start();
		m_started = true;
	}

	/// Block until the connection is closed.
	final void join()
	{
		m_readerThread.join(false);
	}

	final void sendMessage(MsgT)(immutable MsgT msg)
	{
		if (m_closed)
			return;
		sendBytes(Protocol.marshal(msg));
	}

	/// send asynchroniously (caller thread does not block)
	final void sendBytes(immutable(ubyte)[] data)
	{
		if (m_closed)
			return;
		if (atomicOp!"+="(m_writeQueueSize, 1) > 128)
		{
			error(conId, " write queue overflow, closing");
			close();
			return;
		}
		send!(immutable(ubyte)[])(m_writerThread, data);
	}

	/// send raw bytes to the peer
	private void sendBytesSync(const(ubyte)[] msgBody)
	{
		ptrdiff_t toSend = msgBody.length.to!ptrdiff_t;
		while (toSend != 0)
		{
			assert(toSend > 0);
			auto sent = m_sock.send(msgBody[$-toSend .. $]);
			assert(sent <= toSend);
			if (sent <= Socket.ERROR)
			{
				version(Posix)
				{
					if (errno == EINTR)
						continue;
				}
				throw new ConnectionException(lastSocketError());
			}
			else
				toSend -= sent;
		}
	}

	/// Set handler for protocol message of type MsgT. Should only be called once.
	final void setHandler(MsgT)(void delegate(MsgT msg) handler)
	{
		assert(handler);
		assert(m_handlers[MsgT.g_marshIdx] is null);
		m_handlers[MsgT.g_marshIdx] =
			(ubyte[] msgBody) { handler(Protocol.demarshal!MsgT(msgBody)); };
	}

	/// ditto
	final void setHandler(MsgT)(void delegate(MsgT msg, ubyte[] rawBody) handler)
	{
		assert(handler);
		assert(m_handlers[MsgT.g_marshIdx] is null);
		m_handlers[MsgT.g_marshIdx] =
			(ubyte[] msgBody) { handler(Protocol.demarshal!MsgT(msgBody), msgBody); };
	}

	/// synchronous close
	final void close()
	{
		assert(m_started);
		// connection will be closed once
		if (!cas(&m_closed, false, true))
			return;
		info(conId, " Closing connection to ", m_remoteAddr);
		send!WriterMsg(m_writerThread, WriterMsg.TERMINATE);
		doClose();
	}

	private void doClose()
	{
		m_sock.shutdown(SocketShutdown.BOTH);
		m_sock.close();
	}

	/// Fired asynchronously from writer thread when the connection is closed.
	Event!(void delegate(typeof(this))) onClose;

	// first int - message type, second - body size.
	private int[2] recvHeader()
	{
		int[2] header;
		recvBytes(8, cast(ubyte[]) header);
		enforce!ProtocolException(header[0] >= -1 &&
			header[0] < m_handlers.length.to!int, "Unknown message " ~ header[0].to!string);
		enforce!ProtocolException(header[1] >= 0 &&
			header[1] <= MAX_MSG_SIZE, "Message length invalid");
		// if (header[0] >= 0)
		// 	trace(conId, " received message header ",
		// 		Protocol.msgTypeNames[header[0]], " ", header[1]);
		// else
		// 	trace(conId, " received message header ", header);
		return header;
	}

	private ubyte[] recvBytes(int size, ubyte[] res = null)
	{
		if (res.length == 0)
			res = new ubyte[size];
		else if (res.length < size)
			res.length = size.to!size_t;
		ptrdiff_t toReceive = size;
		while (toReceive != 0)
		{
			assert(toReceive > 0);
			auto received = m_sock.receive(res[$-toReceive .. $]);
			assert(received <= toReceive);
			static assert(Socket.ERROR < 0);
			if (received <= Socket.ERROR)
			{
				version(Posix)
				{
					if (errno == EINTR)
						continue;
				}
				throw new ConnectionException(lastSocketError());
			}
			else if (received == 0)
				throw new ConnectionException("remote peer closed connection");
			else
				toReceive -= received;
		}
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
					handler(recvBytes(header[1]));
				else
					throw new ProtocolException("No handler for message " ~
						Protocol.msgTypeNames[header[0]]);
			}
		}
		catch (ConnectionException e)
		{
			error(conId, " ConnectionException in reader thread: ", e.msg);
			close();
		}
		catch (Exception e)
		{
			error(conId, " Exception caught in reader thread: ", e.toString());
			close();
		}
		catch (Throwable e)
		{
			import core.stdc.stdlib;

			error(conId, " Throwable caught in reader thread: ", e.toString());
			exit(1);
		}
	}

	private void writerProc()
	{
		scope(exit) onClose(this);
		try
		{
			bool exitFlag;
			while(!exitFlag)
			{
				try
				{
					bool timedOut = !receiveTimeout(seconds(10),
						(immutable(ubyte)[] msgBody)
						{
							atomicOp!"-="(m_writeQueueSize, 1);
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
					trace(conId, " swallowing OwnerTerminated");
				}
			}
		}
		catch (Throwable e)
		{
			error(conId, " Throwable caught in writer thread: ", e.msg);
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
				assert(cast(string) req.username == "test");
				msgReceived = true;
			});
		server.start();
		thread2.join();
		client.sendMessage(immutable LoginReq(cast(immutable(ubyte)[]) "test"));
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