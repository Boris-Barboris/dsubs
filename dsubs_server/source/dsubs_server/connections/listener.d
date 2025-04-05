module dsubs_server.connections.listener;

import std.socket;
import std.process: environment;
import core.thread;

import dsubs_common.network.connection;
import dsubs_common.network.listener;

import dsubs_server.common;
import dsubs_server.connections.playercon;
import dsubs_server.email;


final class ConListener
{
	private
	{
		Thread publicEpThread;
		Socket publicSock;
		PlayerConnection[Object] allCons;
	}

	this()
	{
		publicEpThread = new Thread(&publicEndpoint);
	}

	void bindSockets()
	{
		short port = environment.get("DSUBS_PORT", "17855").to!short;
		TcpServer server = TcpServer("0.0.0.0", port);
		publicSock = listenTcp(server);
	}

	void startListeners()
	{
		publicEpThread.start();
	}

	private void removeCon(PlayerConnection con)
	{
		synchronized(this)
		{
			allCons.remove(con);
		}
	}

	private void publicEndpoint()
	{
		scope(failure) error("publicEndpoint thread crashed!");
		while (true)
		{
			try
			{
				serveTcp(publicSock, (Socket s)
				{
					PlayerConnection con = new PlayerConnection(s);
					synchronized(this)
					{
						allCons[con] = con;
					}
					con.onClose += cast(con.onClose.HandlerType) &removeCon;
					con.start();
				});
			}
			catch (SocketAcceptException ex)
			{
				sendMail("dsubs_server serveTcp crash", ex.msg);
				Thread.sleep(seconds(10));
				bindSockets();
			}
		}
	}
}