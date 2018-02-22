module dsubs_client.game.connection;

import std.algorithm;
import std.conv: to;
import std.concurrency;
import std.exception;
import std.experimental.logger;
import std.socket;
import core.atomic;
import core.sync.mutex;
import core.thread;

import dsubs_common.api;
import dsubs_common.event;


/// TCP connection to dsubs server
final class ServerConnection
{
	private
	{
		Socket m_sock;
		Address m_serverAddr;

		Thread m_readerThread;	/// this thread reads messages in infinite loop

		/// This thread writes in infinite loop. It's needed in order to not block main
		/// threads on disconnects.
		Tid m_writerThread;

		void delegate(ubyte[])[] m_handlers;
		Mutex m_mutex;
		shared bool m_connected;
		bool m_writerRunning;
		shared bool m_closed;
	}

	/// Create the connection object and spool up worker threads.
	/// 'lockToHold' is a mutex guarding event objects.
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
		m_handlers[LoginRes.g_marshIdx] = &h_generic!(LoginRes, "onLoginRes");
		m_handlers[SessionClosedRes.g_marshIdx] = &h_sessionClosed;
		m_handlers[EntityDbRes.g_marshIdx] = &h_generic!(EntityDbRes, "onEntityDbRecieved");
		m_handlers[SpawnRes.g_marshIdx] = &h_generic!(SpawnRes, "onSpawnRes");
		m_handlers[SubKinematicRes.g_marshIdx] = &h_generic!(SubKinematicRes, "onSubKinematicRes");
		m_handlers[ReconnectStateRes.g_marshIdx] = &h_generic!(ReconnectStateRes, "onReconnectStateRes");

		do_connect();
	}

	/// Close connection and do not reconnect. Returns true when actual
	/// socket closing was performed by this call.
	bool close(string reason = "unspecified", bool raiseEvent = true)
	{
		if (!cas(&m_closed, false, true))
			return false;
		trace("Closing connection ", m_serverAddr);
		atomicStore(m_connected, false);
		if (raiseEvent)
		{
			synchronized(m_mutex)
				onConnectionClosed(reason);
		}
		m_sock.shutdown(SocketShutdown.BOTH);
		m_sock.close();
		if (m_writerRunning)
			send!(int, immutable(void)*)(m_writerThread, 0, null);
		return true;
	}

	/// True when tcp connection is supposedly alive and dsubs server responded
	/// with ServerStatusRes
	@property bool connected() const { return atomicLoad(m_connected); }

	/// Last value of received ServerStatusRes
	ServerStatusRes lastServerStatus;

	/// asynchronously send protocol message to the server
	void sendMessage(MsgT)(immutable(MsgT)* msgPtr)
	{
		send!(int, immutable(void)*)(
			m_writerThread, MsgT.g_marshIdx, cast(immutable(void)*) msgPtr);
	}

	// clear all handlers from events
	void clearHandlers()
	{
		onConnectionClosed.clear();
		onConnectionSuccess.clear();
		onLoginRes.clear();
		onEntityDbRecieved.clear();
		onSpawnRes.clear();
		onSubKinematicRes.clear();
		onReconnectStateRes.clear();
	}

	// Subscribe to these events. They are all fired while holding m_mutex.
	Event!(void delegate(string reason)) onConnectionClosed;
	Event!(void delegate(ServerStatusRes res)) onConnectionSuccess;
	Event!(void delegate(LoginRes res)) onLoginRes;
	Event!(void delegate(EntityDbRes res)) onEntityDbRecieved;
	Event!(void delegate(SpawnRes res)) onSpawnRes;
	Event!(void delegate(SubKinematicRes res)) onSubKinematicRes;
	Event!(void delegate(ReconnectStateRes res)) onReconnectStateRes;

private:

	void do_connect()
	{
		atomicStore(m_closed, false);
		m_readerThread = new Thread(&readProc).start();
	}

	int[2] recvHeader()
	{
		int[2] header;
		auto received = m_sock.receive(header);
		enforce(received == 8, "Error during receive");
		enforce(header[0] >= 0 && header[0] < g_msgDemarshallers.length, "Unknown message");
		enforce(header[1] >= 0 && header[1] <= MAX_MSG_SIZE, "Message length invalid");
		//trace("received header ", header);
		return header;
	}

	ubyte[] recvBody(int size)
	{
		ubyte[] res = new ubyte[size];
		auto received = m_sock.receive(res);
		enforce(received == size, "Error during receive");
		return res;
	}

	void sendBody(immutable(ubyte)[] msgBody)
	{
		auto sent = m_sock.send(msgBody);
		enforce(sent == msgBody.length, "Error during send");
	}

	void readProc()
	{
		m_sock = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.IP);
		bool tcpConnected = false;
		while (!tcpConnected)
		{
			try
			{
				m_sock.connect(m_serverAddr);
				tcpConnected = true;
				m_writerThread = spawn(cast(shared void delegate()) &writerProc);
				m_writerRunning = true;
			}
			catch (Exception e)
			{
				error("Error during connect: ", e.msg);
				if (atomicLoad(m_closed))
					return;
				Thread.sleep(seconds(10));
			}
		}
		try
		{
			{
				immutable ServerStatusReq req;
				sendBody(marshalMessage(&req));
			}
			while (true)
			{
				int[2] header = recvHeader();
				if (header[0] < 0 || header[0] >= m_handlers.length)
					throw new Exception("Invalid message header");
				void delegate(ubyte[]) handler = m_handlers[header[0]];
				if (handler)
				{
					ubyte[] msgBody = recvBody(header[1]);
					handler(msgBody);
				}
				else
					throw new Exception("Unexpected message header");
			}
		}
		catch (Exception e)
		{
			error(e.toString());
			reset(e.msg);
		}
	}

	void reset(string reason)
	{
		if (close(reason))
		{
			trace("Sleeping for 5 seconds");
			Thread.sleep(seconds(5));
			info("Attempting reconnect...");
			do_connect();
		}
	}

	void writerProc()
	{
		scope(exit) m_writerRunning = false;
		try
		{
			while (true)
			{
				auto msg = receiveOnly!(int, immutable(void)*)();
				if (msg[1] == null && msg[0] == 0)
				{
					trace("Interpretting null message as writer stop signal");
					return;
				}
				auto msgBody = g_msgMarshallers[msg[0]](msg[1]);
				sendBody(msgBody);
			}
		}
		catch (Exception e)
		{
			error("TCP writer thread crashed: ", e.toString());
		}
	}

	void h_serverStatus(ubyte[] msgBody)
	{
		ServerStatusRes res;
		demarshalMessage(&res, msgBody);
		info("TCP connection to server established");
		atomicStore(m_connected, true);
		lastServerStatus = res;
		synchronized(m_mutex)
			onConnectionSuccess(res);
	}

	void h_generic(MsgT, string eventName)(ubyte[] msgBody)
	{
		MsgT res;
		demarshalMessage(&res, msgBody);
		synchronized(m_mutex)
			__traits(getMember, this, eventName)(res);
	}

	void h_sessionClosed(ubyte[] msgBody)
	{
		SessionClosedRes res;
		demarshalMessage(&res, msgBody);
		throw new Exception(res.reason);
	}
}