module dsubs_server.connection;

import std.algorithm;
import std.exception;
import std.conv: to;
import std.socket;
import core.thread;
import core.sync.mutex;

import dsubs_common.api;

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
		Thread m_readerThread;
		bool m_authorized = false;
		string m_username, m_password;
		void delegate(ubyte[])[] m_handlers;
	}

	this(Socket sock)
	{
		m_sock = sock;
		sock.setKeepAlive(10, 10);
		m_readerThread = new Thread(&readProc).start();
		m_handlers.length = g_msgDemarshallers.length;
		m_handlers[ServerStatusReq.g_marshIdx] = &h_serverStatus;
		m_handlers[LoginReq.g_marshIdx] = &h_loginReq;
	}

	void close()
	{
		trace("Closing connection ", m_sock.remoteAddress);
		m_sock.close();
		removeConnection(this);
	}

	@property string username() const { return m_username; }

private:

	int[2] recvHeader()
	{
		int[2] header;
		auto received = m_sock.receive(header);
		enforce(received == 8, "Message header is wrong");
		enforce(header[0] >= 0 && header[0] < g_msgDemarshallers.length, "Unknown message");
		enforce(header[1] >= 0 && header[1] < MAX_MSG_SIZE, "Message length invalid");
		return header;
	}

	ubyte[] recvBody(int size)
	{
		ubyte[] res = new ubyte[size];
		auto received = m_sock.receive(res);
		enforce(received == size, "Could not read requested amount of data");
		return res;
	}

	void sendBody(ubyte[] body)
	{
		auto sent = m_sock.send(body);
		enforce(sent == body.length, "Could not send requested amount of data");
	}

	void readProc()
	{
		Thread.sleep(msecs(10));
		try
		{
			while (true)
			{
				int[2] header = recvHeader();
				void delegate(ubyte[]) handler = m_handlers[header[0]];
				if (handler)
				{
					ubyte[] msgBody = recvBody(header[1]);
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

	void h_serverStatus(ubyte[] msgBody)
	{
		ServerStatusReq msg;
		demarshalMessage(&msg, msgBody);
		ServerStatusRes res = ServerStatusRes(API_VERSION,
			g_authorizedConnections.length);
		sendBody(marshalMessage(&res));
	}

	void h_loginReq(ubyte[] msgBody)
	{
		if (m_authorized)
			throw new Exception("Cannot authorize twice");
		LoginReq msg;
		demarshalMessage(&msg, msgBody);
		m_username = msg.username;
		m_password = msg.password;
		if (confirmConnection(this))
		{
			m_authorized = true;
			LoginRes res = LoginRes(true, "Welcome to dsubs server");
			sendBody(marshalMessage(&res));
		}
		else
		{
			LoginRes res = LoginRes(false);
			sendBody(marshalMessage(&res));
		}
	}
}