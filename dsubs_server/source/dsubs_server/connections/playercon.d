module dsubs_server.connections.playercon;

import std.socket;

import core.atomic;

import dsubs_common.api;
import dsubs_common.api.protocols.backend;
import dsubs_common.api.encryption;
import dsubs_common.network.connection;

import dsubs_server.common;
import dsubs_server.player;

private immutable string backendPrivKey = `AAAAQIhNNOl1mtHa10rEmT2cNlHRPpPnRZjbcKDVkxQ632xXvalu5FR+TBVntVprWNSWdU8+8eU9NEZTQM2J2+XCzwGFDL8MsqmcEiIcX75poV2js3UKvpoV7l8aQ/i7mWSg+Z0nLrhqJOk9Jc4gU7gUmUOkF5lECIoUC8QUm496M5Xz`;


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
				// we are already spawned
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
			sendMessage(immutable LoginRes(false, aex.msg,
				Globals.entityDb.commonEntityDbHash, false));
		}
	}

	void h_entityDbReq(EntityDbReq req)
	{
		sendBytes(Globals.entityDb.marshalledCommonEntityDb);
	}

	void h_spawnReq(SpawnReq req)
	{
		Player p = m_player;
		enforce!AuthException(p, "unauthorized");
		immutable(ReconnectStateRes) rres = p.handleSpawnRequest(req);
		sendMessage(immutable SpawnRes(true));
		sendMessage(rres);
		m_simulatorFlow = true;
	}

	void h_reconnectReq(ReconnectReq req)
	{
		Player p = m_player;
		enforce!AuthException(p, "unauthorized");
		synchronized(Globals.simMut.reader)
		{
			sendMessage(p.getReconnectState());
			m_simulatorFlow = true;
		}
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
		p.handleEmitPingRequest(req);
	}
}