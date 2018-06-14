module dsubs_server.connections.listener;

import std.socket;
import core.thread;

import dsubs_common.network.connection;
import dsubs_common.network.listener;

import dsubs_server.common;
import dsubs_server.connections.playercon;


final class ConListener
{
	private
	{
		Thread publicEpThread;
		Socket publicSock;
		Object[Object] allCons;
	}

	this()
	{
		publicEpThread = new Thread(&publicEndpoint);
	}

	void startListeners()
	{
		publicEpThread.start();
	}

	private void publicEndpoint()
	{
		TcpServer server = TcpServer("0.0.0.0", 17855);
		serveTcp(server, publicSock, (Socket s)
		{
			PlayerConnection con = new PlayerConnection(s);
			allCons[con] = con;
			con.onClose += (c) { allCons.remove(c); };
			con.start();
		});
	}
}