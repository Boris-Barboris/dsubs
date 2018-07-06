module dsubs_client.game.connections.cicclient;

import std.socket;

import dsubs_common.api;
import dsubs_common.api.protocol;
import dsubs_common.api.protocols.backend;
import dsubs_common.network.connection;

import dsubs_client.game.cic.messages;
import dsubs_client.game.cic.protocol;
import dsubs_client.common;
import dsubs_client.core.utils;
import dsubs_client.game;


/// TCP connection to CIC server.
final class CICClientConnection: ProtocolConnection!CICProtocol
{
	this(Socket sock)
	{
		super(sock);
	}

	/// synchronous (in caller thread) connect to CIC server
	static CICClientConnection connect(string url, string password)
	{
		Socket clientSock = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.IP);
		auto addr = new InternetAddress(url, 17900);
		info("Attempting to connect to CIC server ", addr);
		clientSock.connect(addr);
		auto con = new CICClientConnection(clientSock);
		con.onClose += (c)
			{
				synchronized(Game.mainMutex)
					Game.activeState.handleCICDisconnect();
			};
		con.start();
		con.sendMessage(immutable CICLoginReq(password));
		return con;
	}

private:

	void h_loginRes(CICLoginRes res)
	{
		CICLoginRes expected;
		if (res.apiVersion != expected.apiVersion)
			throw new Exception("Incompatible CIC api versions");
	}

	void h_SubKinematicRes(SubKinematicRes res)
	{
		synchronized(Game.mainMutex)
		{

		}
	}
}