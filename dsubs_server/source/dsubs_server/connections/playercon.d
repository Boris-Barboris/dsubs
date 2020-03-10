module dsubs_server.connections.playercon;

import std.socket;
import std.zlib;
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

private immutable string backendPrivKey = `AAAAQIhNNOl1mtHa10rEmT2cNlHRPpPnRZjbcKDVkxQ632xXvalu5FR+TBVntVprWNSWdU8+8eU9NEZTQM2J2+XCzwGFDL8MsqmcEiIcX75poV2js3UKvpoV7l8aQ/i7mWSg+Z0nLrhqJOk9Jc4gU7gUmUOkF5lECIoUC8QUm496M5Xz`;


/// Backend side of a protocol connection. Cannot be authorized
/// twice, and the player can have at most one connection open.
final class PlayerConnection: ProtocolConnection!BackendProtocol
{
	private
	{
		Player m_player;
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

	void h_loginReq(LoginReq req)
	{
		enforce!AuthException(m_player is null, "already authorized");
		try
		{
			m_backendPrivKeyInfo = RSA.decodeKey(backendPrivKey);
			m_player = Globals.players.authorizeConnection(this,
				decrypt(req.username, &m_backendPrivKeyInfo),
				decrypt(req.password, &m_backendPrivKeyInfo));
			if (m_player.submarine)
			{
				info("Player is already spawned");
				sendMessage(immutable LoginRes(true, "Welcome",
					Globals.entityDb.commonEntityDbHash, true));
			}
			else
			{
				// we have no submarine
				sendMessage(immutable LoginRes(true, "Welcome",
					Globals.entityDb.commonEntityDbHash, false));
			}
		}
		catch (AuthException aex)
		{
			Thread.sleep(dur!"seconds"(2));
			sendMessage(immutable LoginRes(false, aex.msg,
				Globals.entityDb.commonEntityDbHash, false));
			throw aex;
		}
	}

	void h_entityDbReq(EntityDbReq req)
	{
		sendMessage(immutable EntityDbRes(
			Globals.entityDb.marshalledCommonEntityDb.length.to!int,
			Globals.entityDb.compressedCommonEntityDb
		));
	}

	void h_spawnReq(SpawnReq req)
	{
		Player p = m_player;
		enforce!AuthException(p, "unauthorized");
		info("Handling spawn request for ", p.name);
		immutable(ReconnectStateRes) rres = p.handleSpawnRequest(req, Globals.mainArenaSim);
		sendMessage(immutable SpawnRes(true));
		sendMessage(rres);
		m_simulatorFlow = true;
	}

	void h_reconnectReq(ReconnectReq req)
	{
		Player p = m_player;
		enforce!AuthException(p, "unauthorized");
		info("Sending reconnect state to ", p.name);
		auto sub = p.submarine;
		enforce(sub !is null, "Player does not have a sub");
		ReconnectStateRes res;
		synchronized(sub.simulator.simMut.reader)
		{
			res = cast() p.getReconnectState();
			m_simulatorFlow = true;
		}
		sendMessage(cast(immutable) res);
	}

	void enforceAuthAndSim(Player p)
	{
		enforce!AuthException(p, "unauthorized");
		enforce!Exception(m_simulatorFlow, "not in simulator flow");
	}

	void h_throttleReq(ThrottleReq req)
	{
		Player p = m_player;
		enforceAuthAndSim(p);
		p.handleThrottleRequest(req);
	}

	void h_courseReq(CourseReq req)
	{
		Player p = m_player;
		enforceAuthAndSim(p);
		p.handleCourseRequest(req);
	}

	void h_listenDirReq(ListenDirReq req)
	{
		Player p = m_player;
		enforceAuthAndSim(p);
		p.handleListenDirRequest(req);
	}

	void h_emitPingReq(EmitPingReq req)
	{
		Player p = m_player;
		enforceAuthAndSim(p);
		info(p.name, " requests ping");
		p.handleEmitPingRequest(req);
	}

	void h_loadTubeReq(LoadTubeReq req)
	{
		Player p = m_player;
		enforceAuthAndSim(p);
		p.handleLoadTubeReq(req);
	}

	void h_setTubeStateReq(SetTubeStateReq req)
	{
		Player p = m_player;
		enforceAuthAndSim(p);
		p.handleSetTubeStateReq(req);
	}

	void h_launchTubeReq(LaunchTubeReq req)
	{
		Player p = m_player;
		enforceAuthAndSim(p);
		info(p.name, " requests tube launch: ", req);
		p.handleLaunchTubeReq(req);
	}

	void h_wireDesiredLengthReq(WireDesiredLengthReq req)
	{
		Player p = m_player;
		enforceAuthAndSim(p);
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
			immutable (ReplaySlice[]) slices = cast(immutable)
				Globals.metrics.queryReplaySlices(req.simulatorInstance, from, until);
			ReplayDataRes res = ReplayDataRes(req.metricsDate);
			getArrayMarshLen(slices, res.uncompressedLength);
			ubyte[] buf;
			buf.length = res.uncompressedLength.to!size_t;
			ubyte[] bufSlice = buf;
			marshalArray(slices, bufSlice);
			res.compressedReplaySlices = compress(buf, 6);
			trace("compressed ", res.uncompressedLength, " replay bytes to ", res.compressedReplaySlices.length);
			sendMessage(cast(immutable) res);
		}
	}
}
