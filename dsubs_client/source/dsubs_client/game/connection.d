module dsubs_client.game.connection;

import std.algorithm;
import std.conv: to;
import std.concurrency;
import std.exception;
import std.experimental.logger;
import std.socket;
import core.sync.mutex;

import dsubs_common.api;
import dsubs_common.event;


/// TCP connection to dsubs server
final class ServerConnection
{
	private
	{
		Socket m_sock;
		Address m_serverAddr;

		Tid m_readerThread;	/// this thread reads messages in infinite loop

		/// This one writes in infinite loop. It's needed in order to not block main
		/// threads on disconnects.
		Tid m_writerThread;

		void delegate(ubyte[])[] m_handlers;
		Mutex m_mutex;
		bool m_connected;
	}

	this(string serverAddr, Mutex lockToHold)
	{
		assert(lockToHold);
		m_mutex = lockToHold;
		assert(serverAddr);
		m_serverAddr = getAddress(serverAddr, 13337)[0];
		enforce(m_serverAddr !is null, "Could not parse server address");

		// setup handlers
		m_handlers.length = g_msgDemarshallers.length;
		m_handlers[ServerStatusRes.g_marshIdx] = &h_serverStatus;
		m_handlers[LoginRes.g_marshIdx] = &h_loginRes;

		m_sock = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.IP);
		m_readerThread = spawn(cast(shared void delegate()) &readProc);
		m_writerThread = spawn(cast(shared void delegate()) &writerProc);
	}

	void close()
	{
		trace("Closing connection ", m_serverAddr);
		m_connected = false;
		onConnectionClosed();
		try { m_sock.close(); } catch (SocketOSException e) { trace(e.msg); }
		send!(int, immutable(void)*)(m_writerThread, 0, null);
	}

	@property bool connected() const { return m_connected; }

	ServerStatusRes lastServerStatus;

	void sendMessage(MsgT)(immutable(MsgT)* msgPtr)
	{
		send!(int, immutable(void)*)(
			m_writerThread, MsgT.g_marshIdx, cast(immutable(void)*) msgPtr);
	}

	// clear all events from handlers
	void clearHandlers()
	{
		onConnectionClosed.clear();
		onConnectionSuccess.clear();
		onLoginRes.clear();
	}

	// subscribe to these events
	Event!(void delegate()) onConnectionClosed;
	Event!(void delegate(ServerStatusRes res)) onConnectionSuccess;
	Event!(void delegate(LoginRes res)) onLoginRes;

private:

	int[2] recvHeader()
	{
		int[2] header;
		auto received = m_sock.receive(header);
		enforce(received != Socket.ERROR, "Socket was closed");
		enforce(received == 8, "Could not recieve message header");
		enforce(header[0] >= 0 && header[0] < g_msgDemarshallers.length, "Unknown message");
		enforce(header[1] >= 0 && header[1] < MAX_MSG_SIZE, "Message length invalid");
		trace("recieved header", header);
		return header;
	}

	ubyte[] recvBody(int size)
	{
		ubyte[] res = new ubyte[size];
		auto received = m_sock.receive(res);
		enforce(received != Socket.ERROR, "Socket was closed");
		enforce(received == size, "Could not read requested amount of data");
		return res;
	}

	void sendBody(immutable(ubyte)[] msgBody)
	{
		auto sent = m_sock.send(msgBody);
		enforce(sent != Socket.ERROR, "Socket was closed");
		enforce(sent == msgBody.length, "Could not send requested amount of data");
	}

	void readProc()
	{
		try
		{
			m_sock.connect(m_serverAddr);
			{
				immutable ServerStatusReq req;
				sendBody(marshalMessage(&req));
			}
			while (true)
			{
				int[2] header = recvHeader();
				void delegate(ubyte[]) handler = m_handlers[header[0]];
				if (handler)
				{
					ubyte[] msgBody = recvBody(header[1]);
					m_mutex.lock();
					scope(exit) m_mutex.unlock();
					handler(msgBody);
				}
				else
					throw new Exception("Unacceptable message header");
			}
		}
		catch (Exception e)
		{
			trace(e.toString);
			close();
		}
	}

	void writerProc()
	{
		try
		{
			while (true)
			{
				auto msg = receiveOnly!(int, immutable(void)*)();
				if (msg[1] == null && msg[0] == 0)
				{
					trace("Interpretting null message as stop signal");
					return;
				}
				auto msgBody = g_msgMarshallers[msg[0]](msg[1]);
				sendBody(msgBody);
			}
		}
		catch (Exception e)
		{
			trace(e.toString);
			trace("TCP writer thread stopped");
		}
	}

	void h_serverStatus(ubyte[] msgBody)
	{
		ServerStatusRes res;
		demarshalMessage(&res, msgBody);
		info("TCP connection to server established");
		m_connected = true;
		lastServerStatus = res;
		onConnectionSuccess(res);
	}

	void h_loginRes(ubyte[] msgBody)
	{
		LoginRes res;
		demarshalMessage(&res, msgBody);
		onLoginRes(res);
	}
}