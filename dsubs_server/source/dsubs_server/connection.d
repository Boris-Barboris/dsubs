module dsubs_server.connection;

import std.algorithm;
import std.exception;
import std.concurrency;
import std.conv: to;
import std.socket;
import core.sync.mutex;

import dsubs_common.api;
import dsubs_common.event;

import dsubs_server.common;


private __gshared
{
	Mutex g_conMut;
	PlayerConnection[] g_freshConnections;
	PlayerConnection[string] g_authorizedConnections;
}

shared static this()
{
	g_conMut = new Mutex();
}

void addNewConnection(PlayerConnection pc)
{
	g_conMut.lock();
	scope(exit) g_conMut.unlock();
	g_freshConnections ~= pc;
}

private bool confirmConnection(PlayerConnection pc)
{
	g_conMut.lock();
	scope(exit) g_conMut.unlock();
	PlayerConnection* existing = pc.username in g_authorizedConnections;
	if (existing)
	{
		if (existing.m_password != pc.m_password)
			return false;
		existing.close();
	}
	g_authorizedConnections[pc.username] = pc;
	g_freshConnections = g_freshConnections.remove!(a => a is pc);
	return true;
}

private void removeConnection(PlayerConnection pc)
{
	g_conMut.lock();
	scope(exit) g_conMut.unlock();
	if (pc.m_authorized)
		g_authorizedConnections.remove(pc.username);
	else
		g_freshConnections = g_freshConnections.remove!(a => a is pc);
}


final class PlayerConnection
{
	private
	{
		Socket m_sock;
		Mutex m_mutex;
		Address m_remoteAddr;
		Tid m_readerThread;
		Tid m_writerThread;
		bool m_authorized = false;
		string m_username, m_password;
		void delegate(ubyte[])[] m_handlers;
	}

	this(Socket sock, Mutex lockToHold)
	{
		m_sock = sock;
		m_mutex = lockToHold;
		sock.setKeepAlive(10, 10);
		m_remoteAddr = sock.remoteAddress();

		// fill handlers
		m_handlers.length = g_msgDemarshallers.length;
		m_handlers[ServerStatusReq.g_marshIdx] = &h_serverStatus;
		m_handlers[LoginReq.g_marshIdx] = &h_loginReq;

		// std is not very good with shared, we'll have to cast it hard to 
		// make it work
		m_readerThread = spawn(cast(shared void delegate()) &readProc);
		m_writerThread = spawn(cast(shared void delegate()) &writerProc);
	}

	void sendMessage(MsgT)(immutable(MsgT)* msgPtr)
	{
		send!(int, immutable(void)*)(
			m_writerThread, MsgT.g_marshIdx, cast(immutable(void)*) msgPtr);
	}

	void close()
	{
		trace("Closing connection ", m_remoteAddr);
		try { m_sock.close(); } catch (Exception e) { trace(e.msg); }
		send!(int, immutable(void)*)(m_writerThread, 0, null);
		removeConnection(this);
	}

	@property string username() const { return m_username; }

private:

	int[2] recvHeader()
	{
		int[2] header;
		auto received = m_sock.receive(header);
		enforce(received != Socket.ERROR, "Socket was closed");
		enforce(received == 8, "Message header is wrong");
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
			trace(e.msg);
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
			trace(e.msg);
			trace("TCP writer thread stopped");
		}
	}

	void h_serverStatus(ubyte[] msgBody)
	{
		ServerStatusReq msg;
		demarshalMessage(&msg, msgBody);
		immutable ServerStatusRes res = ServerStatusRes(API_VERSION,
			g_authorizedConnections.length);
		trace("Responding with ", res);
		sendBody(marshalMessage(&res));
	}

	void h_loginReq(ubyte[] msgBody)
	{
		if (m_authorized)
			throw new Exception("Cannot authorize twice");
		LoginReq msg;
		demarshalMessage(&msg, msgBody);
		if (msg.username.length < 1)
		{
			immutable LoginRes res = LoginRes(false, "Enter nonempty username");
			trace("Responding with ", res);
			sendBody(marshalMessage(&res));
			return;
		}
		m_username = msg.username;
		m_password = msg.password;
		trace("Authorizing as: ", m_username);
		if (confirmConnection(this))
		{
			m_authorized = true;
			immutable LoginRes res = LoginRes(true, "Welcome to dsubs server");
			trace("Responding with ", res);
			sendBody(marshalMessage(&res));
		}
		else
		{
			immutable LoginRes res = LoginRes(false, "Invalid password");
			trace("Responding with ", res);
			sendBody(marshalMessage(&res));
		}
	}
}