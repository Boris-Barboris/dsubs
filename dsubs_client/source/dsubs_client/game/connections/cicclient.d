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
import dsubs_client.game.states.deathscreen;


/// TCP connection to CIC server.
final class CICClientConnection: ProtocolConnection!CICProtocol
{
	this(Socket sock)
	{
		super(sock);
		this.onClose += (c)
			{
				if (Game.shuttingDown)
					return;
				synchronized(Game.mainMutex)
				{
					// under no circumstance local CIC server should survive
					// local cic connection crash
					if (Game.cic)
						Game.cic.stop();
					Game.activeState.handleCICDisconnect();
				}
			};
		mixinHandlers(this);
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
			throw new Exception("Incompatible CIC api versions. Yours: " ~
				expected.apiVersion.to!string ~ ", server: " ~ res.apiVersion.to!string);
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
			Game.entityDb = res.res;
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

	void h_deathRes(CICDeathRes res)
	{
		synchronized(Game.mainMutex)
		{
			Game.activeState = new DeathScreenState(res);
		}
	}

	void h_SubKinematicRes(CICSubKinematicRes res)
	{
		synchronized(Game.mainMutex)
		{
			Game.simState.updateLastServerTime(res.snap.atTime);
			Game.simState.playerSub.updateKinematics(res.snap);
			Game.simState.playerSub.updateWireKinematics(res.wireSnaps);
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
			Game.simState.gui.waterfall.listenDir = req.dir;
		}
	}

	void h_acousticRes(CICSubAcousticRes res)
	{
		assert(res.data.length == 1);
		assert(res.data[0].hydrophoneIdx == 0);
		StreamingSoundSource s;
		synchronized(Game.mainMutex)
		{
			foreach (AntennaeData antData; res.data[0].antennaes)
			{
				Game.simState.gui.waterfall.drawData(
					antData.beams, res.rotationAtTime, antData.antennaeIdx);
			}
			Game.simState.gui.waterfall.completeRow();
			s = Game.simState.sonarSound;
		}
		if (s && res.audio.length > 0)
		{
			s.pullFinishedBuffers();
			if (s.queuedCount > 0)
				s.append(res.audio[0].samples, res.audio[0].samplingRate);
			else
			{
				// we delay first sample enqueing in order to reduce the risk of buffering
				Game.delay(()
					{
						s.append(res.audio[0].samples, res.audio[0].samplingRate);
					}, msecs(250), null);
			}
		}
	}

	void h_sonarRes(CICSubSonarRes res)
	{
		assert(res.data.length == 1);
		assert(res.data[0].sonarIdx == 0);
		synchronized(Game.mainMutex)
		{
			Game.simState.gui.sonardisp.putSliceData(res.data[0]);
		}
	}

	void h_contactCreatedFromDataRes(CICContactCreatedFromDataRes msg)
	{
		synchronized(Game.mainMutex)
		{
			Game.simState.contactManager.handleContactCreated(msg);
		}
	}

	void h_contactCreatedFromHTrackerRes(CICContactCreatedFromHTrackerRes msg)
	{
		synchronized(Game.mainMutex)
		{
			Game.simState.contactManager.handleContactCreated(msg);
		}
	}

	void h_contactDataReq(CICContactDataReq msg)
	{
		synchronized(Game.mainMutex)
		{
			Game.simState.contactManager.handleContactData(msg.data);
		}
	}

	void h_contactUpdateReq(CICContactUpdateReq msg)
	{
		synchronized(Game.mainMutex)
		{
			Game.simState.contactManager.handleContactUpdate(msg.contact);
		}
	}

	void h_dropContactReq(CICDropContactReq msg)
	{
		synchronized(Game.mainMutex)
		{
			Game.simState.contactManager.handleDropContact(msg.ctcId);
		}
	}

	void h_dropDataReq(CICDropDataReq msg)
	{
		synchronized(Game.mainMutex)
		{
			Game.simState.contactManager.handleDropData(msg.dataId);
		}
	}

	void h_contectMergeReq(CICContactMergeReq msg)
	{
		synchronized(Game.mainMutex)
		{
			Game.simState.contactManager.hadleMergeContact(msg.sourceCtcId, msg.destCtcId);
		}
	}

	void h_waterfallUpdateRes(CICWaterfallUpdateRes msg)
	{
		synchronized(Game.mainMutex)
		{
			assert(msg.hydrophoneIdx == 0);
			auto wto = Game.simState.gui.waterfall.trackerOverlay;
			wto.updatePeaks(msg.peaks);
			auto manager = Game.simState.contactManager;
			foreach (ht; msg.trackers)
				manager.handleTracker(ht);
		}
	}

	void h_updateTrackerReq(CICUpdateTrackerReq msg)
	{
		synchronized(Game.mainMutex)
		{
			assert(msg.tracker.id.sensorIdx == 0);
			auto manager = Game.simState.contactManager;
			manager.handleTracker(msg.tracker);
		}
	}

	void h_dropTrackerReq(CICDropTrackerReq msg)
	{
		synchronized(Game.mainMutex)
		{
			assert(msg.tid.sensorIdx == 0);
			auto manager = Game.simState.contactManager;
			manager.handleDropTracker(msg.tid);
		}
	}

	void h_trimContactData(CICTrimContactData msg)
	{
		synchronized(Game.mainMutex)
		{
			auto manager = Game.simState.contactManager;
			manager.handleTrimContactData(msg.ctcId, msg.olderThan);
		}
	}

	void h_tubeStateUpdateRes(CICTubeStateUpdateRes msg)
	{
		synchronized(Game.mainMutex)
		{
			Game.simState.playerSub.tube(msg.res.tube.tubeId).
				updateFromFullState(msg.res.tube);
		}
	}

	void h_ammoRoomStateUpdateRes(CICAmmoRoomStateUpdateRes msg)
	{
		synchronized(Game.mainMutex)
		{
			Game.simState.playerSub.ammoRoom(msg.res.room.roomId).
				updateFromFullState(msg.res.room);
		}
	}

	void h_mapOverlayUpdateRes(CICMapOverlayUpdateRes msg)
	{
		synchronized(Game.mainMutex)
		{
			Game.simState.tacticalOverlay.updateScenarioElements(msg.res.mapElements);
		}
	}

	void h_chatMessageRes(CICChatMessageRes msg)
	{
		info("received chat message: ", msg.res);
		synchronized(Game.mainMutex)
		{
			Game.simState.gui.handleChatMessage(msg.res.message);
		}
	}
}
