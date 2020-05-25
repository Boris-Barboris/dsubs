module dsubs_server.connections.playercon;

import std.socket;
import std.datetime;

import core.atomic;
import core.thread;
import core.time: days;

import dsubs_common.api;
import dsubs_common.api.entities;
import dsubs_common.api.messages;
import dsubs_common.api.encryption;
import dsubs_common.api.marshalling: marshalArray, getArrayMarshLen;
import dsubs_common.network.connection;

import dsubs_server.common;
import dsubs_server.player;
import dsubs_server.simulator: Simulator;
import dsubs_server.submarine: Submarine;
import dsubs_server.scenario;

private immutable string backendPrivKey = `AAAAQIhNNOl1mtHa10rEmT2cNlHRPpPnRZjbcKDVkxQ632xXvalu5FR+TBVntVprWNSWdU8+8eU9NEZTQM2J2+XCzwGFDL8MsqmcEiIcX75poV2js3UKvpoV7l8aQ/i7mWSg+Z0nLrhqJOk9Jc4gU7gUmUOkF5lECIoUC8QUm496M5Xz`;


/// Backend side of a protocol connection. Cannot be authorized
/// twice, and the player can have at most one connection open.
final class PlayerConnection: ProtocolConnection!BackendProtocol
{
	private
	{
		Player m_player;
		/// True when the connection is sending simulator-related messages to the client.
		/// Requested to be set to true by the client when either spawning or
		/// reconnecting.
		bool m_simulatorFlow;
		RSAKeyInfo m_backendPrivKeyInfo;
	}

	@property Player player() { return m_player; }
	@property void player(Player rhs) { m_player = rhs; }

	@property bool simulatorFlow() const { return m_simulatorFlow; }
	@property void simulatorFlow(bool rhs) { m_simulatorFlow = rhs; }

	this(Socket sock)
	{
		super(sock);
		mixinHandlers(this);
	}

private:

	void h_serverStatus(ServerStatusReq req)
	{
		// instantly reply with status message
		sendMessage(immutable ServerStatusRes(Player.getPlayersOnline()));
	}

	int loginFailureSleep = 2;

	void h_loginReq(LoginReq req)
	{
		enforce!AuthException(m_player is null, "already authorized");
		try
		{
			m_backendPrivKeyInfo = RSA.decodeKey(backendPrivKey);
			m_player = Globals.players.authorizeConnection(this,
				decrypt(req.username, &m_backendPrivKeyInfo),
				decrypt(req.password, &m_backendPrivKeyInfo));
			Submarine sub = m_player.submarine;
			LoginSuccessRes resMsg = LoginSuccessRes(Globals.entityDb.commonEntityDbHash);
			if (sub)
			{
				info("Player is already spawned");
				resMsg.alreadySpawned = true;
				if (sub.simulator.scenario)
				{
					ScenarioSpawner spawner = sub.simulator.scenario.spawner;
					resMsg.simulatorScenarioName = spawner.constants.name;
					resMsg.simulatorScenarioType = spawner.scenarioType;
				}
			}
			loginFailureSleep = 2;
			sendMessage(cast(immutable) resMsg);
			if (resMsg.alreadySpawned)
				return;
			// not-spawned user needs available scenarios.
			immutable AvailableScenariosRes scenMsg =
				Globals.scenarioDb.getScenarioResForPlayer(m_player);
			sendMessage(scenMsg);
		}
		catch (AuthException aex)
		{
			Thread.sleep(dur!"seconds"(loginFailureSleep));
			// simple backoff
			if (loginFailureSleep < 60 * 30)
				loginFailureSleep *= 2;
			sendMessage(immutable LoginFailureRes(aex.msg));
		}
	}

	void h_entityDbReq(EntityDbReq req)
	{
		sendBytes(Globals.entityDb.marshalledCommonEntityDb);
	}

	void h_availableScenariosReq(AvailableScenariosReq req)
	{
		Player p = m_player;
		enforceAuth(p);
		immutable AvailableScenariosRes resMsg =
			Globals.scenarioDb.getScenarioResForPlayer(p);
		sendMessage(cast(immutable) resMsg);
	}

	void h_spawnReq(SpawnReq req)
	{
		Player p = m_player;
		enforceAuth(p);
		info("Handling spawn request for ", p.name);
		try
		{
			immutable(ReconnectStateRes) rres =
				p.handleSpawnRequest(req);
			sendMessage(rres);
			m_simulatorFlow = true;
		}
		catch (Exception ex)
		{
			error("spawn failure: ", ex.toString());
			sendMessage(immutable SpawnFailureRes(ex.msg));
		}
	}

	void h_abandonReq(AbandonReq req)
	{
		Player p = m_player;
		enforceAuth(p);
		info("Handling abandon request for ", p.name);
		auto sub = p.submarine;
		enforce(sub !is null, "Player does not have a sub");
		Simulator sim = sub.simulator;
		enforce(sim !is null, "Submarine's simulator is unset");
		synchronized(sim.simMut.reader)
		{
			sim.terminateAsync();
		}
		// simulator will asynchronously self-destruct and notify the connection
		// with SimulatorTerminatingRes.
	}

	void h_reconnectReq(ReconnectReq req)
	{
		Player p = m_player;
		enforceAuth(p);
		info("Sending reconnect state to ", p.name);
		auto sub = p.submarine;
		enforce(sub !is null, "Player does not have a sub");
		ReconnectStateRes res;
		synchronized(sub.simulator.simMut.reader)
		{
			enforce(!sub.simulator.finished, "simulator is finished");
			res = cast() p.getReconnectState();
			m_simulatorFlow = true;
		}
		sendMessage(cast(immutable) res);
	}

	/// Return false if not in simulator message flow.
	void enforceAuth(Player p)
	{
		enforce!AuthException(p, "unauthorized");
	}

	void h_throttleReq(ThrottleReq req)
	{
		Player p = m_player;
		enforceAuth(p);
		p.handleThrottleRequest(req);
	}

	void h_courseReq(CourseReq req)
	{
		Player p = m_player;
		enforceAuth(p);
		p.handleCourseRequest(req);
	}

	void h_listenDirReq(ListenDirReq req)
	{
		Player p = m_player;
		enforceAuth(p);
		p.handleListenDirRequest(req);
	}

	void h_emitPingReq(EmitPingReq req)
	{
		Player p = m_player;
		enforceAuth(p);
		info(p.name, " requests ping");
		p.handleEmitPingRequest(req);
	}

	void h_loadTubeReq(LoadTubeReq req)
	{
		Player p = m_player;
		enforceAuth(p);
		p.handleLoadTubeReq(req);
	}

	void h_setTubeStateReq(SetTubeStateReq req)
	{
		Player p = m_player;
		enforceAuth(p);
		p.handleSetTubeStateReq(req);
	}

	void h_launchTubeReq(LaunchTubeReq req)
	{
		Player p = m_player;
		enforceAuth(p);
		info(p.name, " requests tube launch: ", req);
		p.handleLaunchTubeReq(req);
	}

	void h_wireDesiredLengthReq(WireDesiredLengthReq req)
	{
		Player p = m_player;
		enforceAuth(p);
		p.handleWireDesiredLengthReq(req);
	}

	void h_replayGetDataReq(ReplayGetDataReq req)
	{
		if (Globals.metrics)
		{
			// process request
			Date day = Date.fromISOExtString(req.metricsDate);
			DateTime from = DateTime(day);
			DateTime until = DateTime(day + days(1));
			info("Sending replay data from ", from, " until ", until);
			ReplaySlice[] slices = Globals.metrics.queryReplaySlices(
				req.simulatorInstance, from, until);
			ReplayDataRes res = ReplayDataRes(req.metricsDate, slices);
			sendMessage(cast(immutable) res);
		}
	}
}
