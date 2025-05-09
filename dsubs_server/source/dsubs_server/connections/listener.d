/*
DSubs
Copyright (C) 2017-2025 Baranin Alexander

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
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
		string listenIp = environment.get("DSUBS_LISTEN_IP", "0.0.0.0");
		TcpServer server = TcpServer(listenIp, port);
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