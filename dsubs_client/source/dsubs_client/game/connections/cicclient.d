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
import dsubs_client.game.entities;
import dsubs_client.game.gamestate;
import dsubs_client.game.states.simulation;


/// TCP connection to CIC server.
final class CICClientConnection: ProtocolConnection!CICProtocol
{
	this(Socket sock)
	{
		super(sock);
		this.onClose += (c)
			{
				synchronized(Game.mainMutex)
				{
					Game.activeState.handleCICDisconnect();
				}
			};
		setHandler(&h_loginRes);
		setHandler(&h_reconnectStateRes);
		setHandler(&h_SubKinematicRes);
		setHandler(&h_throttleReq);
		setHandler(&h_courseReq);
		setHandler(&h_entityDbRes);
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

	immutable(ubyte)[] awaitedDbHash;

	void h_loginRes(CICLoginRes res)
	{
		CICLoginRes expected;
		if (res.apiVersion != expected.apiVersion)
			throw new Exception("Incompatible CIC api versions");
		// let's check db versions
		bool requireDb = false;
		synchronized(Game.mainMutex)
		{
			if (res.dbHash != Game.entityDbHash)
			{
				requireDb = true;
				awaitedDbHash = res.dbHash;
			}
		}
		if (requireDb)
		{
			sendMessage(immutable CICEntityDbReq());
			info("requesting entity Database from CIC server");
		}
		else
		{
			assert(Game.entityManager);
			sendMessage(immutable CICEnterSimFlowReq());
			info("entityDb found locally, entering simulation flow");
		}
	}

	void h_entityDbRes(CICEntityDbRes res)
	{
		synchronized(Game.mainMutex)
		{
			Game.entityDbHash = awaitedDbHash;
			Game.entityDb = cast(EntityDbRes) res;
			Game.entityManager = new EntityManager(Game.entityDb);
		}
		sendMessage(immutable CICEnterSimFlowReq());
	}

	void h_reconnectStateRes(CICReconnectStateRes res)
	{
		info("received reconnect state, switching to simulation state");
		synchronized(Game.mainMutex)
		{
			Game.activeState = new SimulatorState(res);
		}
	}

	void h_SubKinematicRes(CICSubKinematicRes res)
	{
		synchronized(Game.mainMutex)
		{
			Game.simState.playerSub.updateKinematics(res.snap);
			Game.simState.gui.handleSubKinematicRes(res);
		}
	}

	void h_throttleReq(CICThrottleReq req)
	{
		synchronized(Game.mainMutex)
		{
			Game.simState.playerSub.targetThrottle = req.target;
			Game.simState.gui.updateTgtThrottleDisplay(req.target);
		}
	}

	void h_courseReq(CICCourseReq req)
	{
		synchronized(Game.mainMutex)
		{
			Game.simState.playerSub.targetCourse = req.target;
			Game.simState.gui.updateTgtCourseDisplay(req.target);
		}
	}
}