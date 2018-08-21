module dsubs_client.game.connections.cicclient;

import core.thread;

import std.socket;

import dsubs_common.api;
import dsubs_common.api.protocol;
import dsubs_common.api.protocols.backend;
import dsubs_common.network.connection;

import dsubs_client.game.cic.messages;
import dsubs_client.game.cic.protocol;
import dsubs_client.common;
import dsubs_client.core.utils;
import dsubs_client.lib.openal;
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
					// under no circumstance local CIC server should survive
					// local cic connection crash
					if (Game.cic)
						Game.cic.stop();
					Game.activeState.handleCICDisconnect();
				}
			};
		setHandler(&h_loginRes);
		setHandler(&h_reconnectStateRes);
		setHandler(&h_SubKinematicRes);
		setHandler(&h_throttleReq);
		setHandler(&h_courseReq);
		setHandler(&h_entityDbRes);
		setHandler(&h_acousticRes);
		setHandler(&h_listenDirReq);
	}

	/// synchronous (in caller thread) connect to CIC server
	static CICClientConnection connect(string url, string password)
	{
		Socket clientSock = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.IP);
		scope(failure) clientSock.close();
		auto addr = parseUrl(url);
		info("Attempting to connect to CIC server ", addr);
		clientSock.connect(addr);
		auto con = new CICClientConnection(clientSock);
		con.start();
		con.sendMessage(immutable CICLoginReq(password));
		return con;
	}

	/// Asynchronously connect to CIC server in background thread.
	/// Returns callback that can be used to abort the attempt to connect.
	static void delegate() connectAsync(string url, string password,
		void delegate(CICClientConnection c) onSuccess,
		void delegate(Exception ex) onFailure)
	{
		Socket clientSock = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.IP);
		auto addr = parseUrl(url);
		info("Attempting to connect to CIC server ", addr);
		Thread thread = new Thread(()
		{
			try
			{
				scope(failure) clientSock.close();
				clientSock.connect(addr);
				auto con = new CICClientConnection(clientSock);
				con.start();
				con.sendMessage(immutable CICLoginReq(password));
				onSuccess(con);
			}
			catch (Exception ex)
			{
				onFailure(ex);
			}
		}).start();
		return () { clientSock.shutdown(SocketShutdown.BOTH); clientSock.close(); };
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
		info("entityDb received from CIC, entering simulation flow");
		sendMessage(immutable CICEnterSimFlowReq());
	}

	void h_reconnectStateRes(CICReconnectStateRes res)
	{
		info("received reconnect state from CIC, switching to simulation state");
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

	void h_listenDirReq(CICListenDirReq req)
	{
		assert(req.hydrophoneIdx == 0);
		synchronized(Game.mainMutex)
		{
			Game.simState.gui.sonarGui.listenDir = req.dir;
		}
	}

	private
	{
		bool m_firstAcousticsData = true;
		// we delay visual information for 1 second to
		// synchronize audio and visual information on the waterfall
		CICSubAcousticRes m_tapAcoustics;
	}

	void h_acousticRes(CICSubAcousticRes res)
	{
		import std.algorithm.iteration: map;
		import std.array: array;

		assert(res.data.length == 1);
		assert(res.data[0].hydrophoneIdx == 0);
		assert(res.data[0].antennaeIdx == 0);
		StreamingSoundSource s;
		synchronized(Game.mainMutex)
		{
			if (m_firstAcousticsData)
			{
				m_firstAcousticsData = false;
				m_tapAcoustics = res;
			}
			else
			{
				Game.simState.gui.sonarGui.drawData(
					m_tapAcoustics.data[0].beams,
					Game.simState.playerSub.tmpl.hydrophones[0].fov,
					m_tapAcoustics.rotationAtTime);
				Game.simState.gui.sonarGui.completeRow();
				m_tapAcoustics = res;
			}
			s = Game.simState.sonarSound;
		}
		if (s && res.audio.length > 0)
		{
			s.pullFinishedBuffers();
			if (s.queuedCount > 0)
				s.append(res.audio[0].samples, res.audio[0].samplingRate);
			else
			{
				// we delay first buffer enqueing in order to reduce the risc of buffering
				Game.delay(()
					{ s.append(res.audio[0].samples, res.audio[0].samplingRate); }, msecs(200), null);
			}
		}
	}
}