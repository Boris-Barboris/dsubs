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
		ushort cicPort = 17900;
		CICServerConnection[Object] allCons;
		CICServer m_cicserv;
		string m_password;
	}

	@property ushort port() const { return cicPort; }

	this(CICServer cicserv, string password)
	{
		m_password = password;
		m_cicserv = cicserv;
		publicEpThread = new Thread(&publicEndpoint);
	}

	void start()
	{
		synchronized(this)
		{
			while (cicPort < 17964)
			{
				try
				{
					TcpServer server = TcpServer("0.0.0.0", cicPort);
					publicSock = listenTcp(server);
					publicEpThread.start();
					info("CIC listening on ", cicPort);
					break;
				}
				catch (SocketOSException ex)
				{
					error("CIC listener start err: ", ex.msg);
					cicPort++;
				}
			}
		}
	}

	/// stop accepting new connections, close all opened ones
	void stop()
	{
		if (!publicSock)
			return;
		info("closing CIC listening socket");
		publicSock.shutdown(SocketShutdown.BOTH);
		publicSock.close();
		synchronized(this)
		{
			foreach (CICServerConnection c; allCons.byValue())
				c.close();
			allCons.clear();
		}
	}

	private void publicEndpoint()
	{
		serveTcp(publicSock, (Socket s)
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

	/// broadcast message to all clients in simulator flow
	void broadcast(immutable(ubyte)[] data)
	{
		foreach (CICServerConnection c; allCons.byValue())
		{
			if (c.inSimFlow)
				c.sendBytes(data);
		}
	}

	/// ditto
	void broadcast(T)(immutable T msg)
		if (is(T == struct))
	{
		broadcast(CICProtocol.marshal(msg));
	}
}