module dsubs_client.game.cic.listener;

import std.socket;
import core.thread;

import dsubs_common.network.connection;
import dsubs_common.network.listener;

import dsubs_client.common;
import dsubs_client.game.connections.cicserver;
import dsubs_client.game.cic.server;
import dsubs_client.game.cic.protocol;


final class CICListener
{
	private
	{
		Thread publicEpThread;
		Socket publicSock;
		CICServerConnection[Object] allCons;
		CICServer m_cicserv;
		string m_password;
	}

	this(CICServer cicserv, string password)
	{
		m_password = password;
		m_cicserv = cicserv;
		publicEpThread = new Thread(&publicEndpoint);
	}

	void start()
	{
		publicEpThread.start();
	}

	/// stop accepting new connections, close all opened ones
	void stop()
	{
		publicSock.close();
		publicSock = null;
		synchronized(this)
		{
			foreach (CICServerConnection c; allCons.byValue())
				c.close();
			allCons.clear();
		}
	}

	private void publicEndpoint()
	{
		TcpServer server = TcpServer("0.0.0.0", 17900);
		serveTcp(server, publicSock, (Socket s)
		{
			auto con = new CICServerConnection(m_cicserv, s, m_password);
			synchronized(this)
			{
				allCons[con] = con;
			}
			con.onClose += cast(con.onClose.HandlerType) &removeCon;
			con.start();
		});
	}

	private void removeCon(CICServerConnection c)
	{
		synchronized(this)
		{
			allCons.remove(c);
		}
	}

	/// broadcast message to all authorized clients
	void broadcast(immutable(ubyte)[] data)
	{
		synchronized(this)
		{
			foreach (CICServerConnection c; allCons.byValue())
			{
				if (c.authorized)
					c.sendBytes(data);
			}
		}
	}

	/// ditto
	void broadcast(T)(immutable T msg)
		if (is(T == struct))
	{
		broadcast(CICProtocol.marshal(msg));
	}
}