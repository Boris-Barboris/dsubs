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


// TODO: take from environment variables maybe?
// secret
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
		// Reverse-reference for refcounting and binding of simflow to
		// a particular simulator. Used to prevent race conditions in
		// Player.onConnectionClose.
		Submarine m_simFlowSub;
		// constructed per-connection because of bugs.
		RSAKeyInfo m_backendPrivKeyInfo;
		// connection for audio and other bulk data streaming
		PlayerConnection m_secondaryConnection;
	}

	@property Player player() { return m_player; }
	@property void player(Player rhs) { m_player = rhs; }

	@property bool simulatorFlow() const { return m_simulatorFlow; }
	@property void simulatorFlow(bool rhs) { m_simulatorFlow = rhs; }

	@property Submarine simFlowSub() { return m_simFlowSub; }
	@property void simFlowSub(Submarine rhs) { m_simFlowSub = rhs; }

	@property PlayerConnection secondaryConnection() { return m_secondaryConnection; }
	@property void secondaryConnection(PlayerConnection rhs)
	{
		m_secondaryConnection = rhs;
	}

	this(Socket sock)
	{
		super(sock);
		mixinHandlers(this);
	}

	@property string secondaryConnectionSecret() const
	{
		return m_secondaryConnectionSecret;
	}

private:

	void h_serverStatus(ServerStatusReq req)
	{
		// instantly reply with status message
		sendMessage(immutable ServerStatusRes(Player.getPlayersOnline()));
	}

	int loginFailureSleep = 2;

	string m_secondaryConnectionSecret;

	void h_loginReq(LoginReq req)
	{
		enforce!AuthException(m_player is null, "already authorized");
		try
		{
			m_backendPrivKeyInfo = RSA.decodeKey(backendPrivKey);
			if (!m_secondaryConnectionSecret)
				m_secondaryConnectionSecret = randomUUID().toString();
			m_player = Globals.players.authorizeConnection(this,
				decrypt(req.username, &m_backendPrivKeyInfo),
				decrypt(req.password, &m_backendPrivKeyInfo),
				m_secondaryConnectionSecret);
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
			resMsg.secondaryConnectionSecret = m_secondaryConnectionSecret;
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
			// simple 2-3-4-...-8 increase
			if (loginFailureSleep < 5)
				loginFailureSleep += 1;
			sendMessage(immutable LoginFailureRes(aex.msg));
		}
	}

	void h_loginSecondaryReq(LoginSecondaryReq req)
	{
		enforce!AuthException(m_player is null, "already authorized");
		try
		{
			m_player = Globals.players.authorizeSecondaryConnection(this,
				req.secondaryConnectionSecret);
			// we are now a secondary connection. Clear message handlers because we
			// are stream-only. Nothing is expected to arrive from the client.
			clearHandlers();
			maxWriteQueueSize = 16;		// reduce to prevent overqueing
		}
		catch (AuthException aex)
		{
			Thread.sleep(dur!"seconds"(loginFailureSleep));
			// simple 2-3-4-...-8 increase
			if (loginFailureSleep < 5)
				loginFailureSleep += 1;
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
		sendMessage(resMsg);
	}

	void h_spawnReq(SpawnReq req)
	{
		Player p = m_player;
		enforceAuth(p);
		info("Handling spawn request for ", p.name);
		try
		{
			p.handleSpawnRequest(req, this);
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
		if (sim.scenario !is null)
		{
			enforce(sim.scenario.spawner.scenarioType != ScenarioType.persistentSimulator,
				"you cannot abandon persistent simulators");
		}
		synchronized(sim.simMut.reader)
		{
			sim.terminateAsync();
		}
		// simulator will asynchronously self-destruct and notify the client
		// by putting SimulatorTerminatingRes into the connection.
	}

	void h_reconnectReq(ReconnectReq req)
	{
		Player p = m_player;
		enforceAuth(p);
		info("Generating reconnect state response for ", p.name);
		synchronized(p)
		{
			auto sub = p.submarine;
			enforce(sub !is null, "Player does not have a sub");
			ReconnectStateRes res;
			synchronized(sub.simulator.simMut.reader)
			{
				enforce(sub is p.submarine, "Submarine has changed after lock");
				res = cast() p.getReconnectState();
				sub.incSubConRefCounter();
				m_simFlowSub = sub;
				p.enableSubSensors(sub);
				sendMessage(cast(immutable) res);
				m_simulatorFlow = true;
			}
		}
	}

	/// Return false if not in simulator message flow.
	private void enforceAuth(Player p)
	{
		enforce!AuthException(p, "unauthorized");
	}

	// Returns player instance or null if not in simFlow. Throws
	// if unauthirozed.
	private Player simFlowValidation()
	{
		Player p = m_player;
		enforceAuth(p);
		// This is a weak non-atomic guard because we don't really
		// mind if the request goes through to the Player class.
		// There it is properly guarded by m_submarine-based conditions under
		// sim lock.
		if (!m_simulatorFlow)
			return null;
		return p;
	}

	void h_throttleReq(ThrottleReq req)
	{
		Player p = simFlowValidation();
		if (p)
			p.handleThrottleRequest(req);
	}

	void h_courseReq(CourseReq req)
	{
		Player p = simFlowValidation();
		if (p)
			p.handleCourseRequest(req);
	}

	void h_listenDirReq(ListenDirReq req)
	{
		Player p = simFlowValidation();
		if (p)
			p.handleListenDirRequest(req);
	}

	void h_emitPingReq(EmitPingReq req)
	{
		Player p = simFlowValidation();
		if (p)
		{
			info(p.name, " requests ping");
			p.handleEmitPingRequest(req);
		}
	}

	void h_loadTubeReq(LoadTubeReq req)
	{
		Player p = simFlowValidation();
		if (p)
			p.handleLoadTubeReq(req);
	}

	void h_setTubeStateReq(SetTubeStateReq req)
	{
		Player p = simFlowValidation();
		if (p)
			p.handleSetTubeStateReq(req);
	}

	void h_launchTubeReq(LaunchTubeReq req)
	{
		Player p = simFlowValidation();
		if (p)
		{
			info(p.name, " requests tube launch: ", req);
			p.handleLaunchTubeReq(req);
		}
	}

	void h_wireGuidanceUpdateParamsReq(WireGuidanceUpdateParamsReq req)
	{
		Player p = simFlowValidation();
		if (p)
			p.handleWireGuidanceUpdateParamsReq(req);
	}

	void h_wireGuidanceActivateReq(WireGuidanceActivateReq req)
	{
		Player p = simFlowValidation();
		if (p)
			p.handleWireGuidanceActivateReq(req);
	}

	void h_wireDesiredLengthReq(WireDesiredLengthReq req)
	{
		Player p = simFlowValidation();
		if (p)
			p.handleWireDesiredLengthReq(req);
	}

	void h_pauseSimulatorReq(PauseSimulatorReq req)
	{
		Player p = simFlowValidation();
		if (p)
			p.handlePauseSimulatorReq(req);
	}

	void h_replayGetDataReq(ReplayGetDataReq req)
	{
		// does not require authorization
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
