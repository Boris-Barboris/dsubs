module dsubs_server.connections.playercon;

import std.socket;

import core.atomic;

import dsubs_common.api;
import dsubs_common.api.protocols.backend;
import dsubs_common.api.encryption;
import dsubs_common.network.connection;

import dsubs_server.common;
import dsubs_server.player;

private immutable string backendPrivKey = `AAABAJPL2uFvPdhups3a/ZFvv9lyZRaR0SbWsfLln8s4hqXDNOw8OWYnmPaNu5bsvDSAfccT4BatH8MR92nuBYAy0Nny7E6Tzs0MWZfj/zIGd4XWqIbq0WKsSosa3xSPmL1+0LmDcLg9NnWgeUjNWfNUvGnANm1XqbVvQeCkRhq3p91eftOYkS/jyTwszZZKOVyW4DkP4hk9+jY5w5860VYKBxE9ClPA8LCeBWIf6PUAXZxP722Gqdgg7cAbMdmbgjs7BhuWC7do4Rk7Pric7+VFp/A7noDMYW+mby+n5OYSS5G7RN6yRlit9QVFfYlqfJzCwu6yKTYelmCFH2hESNr8flEOO2JdfDWM06JVPJZwASRQEmAdH3o/b4VfZLeHwWAS6Lm1IqgBuASWNSftrH+oNBmKo72bsWM7oPkoa+uCZkGDZJAlyaU4EUHkUt64G4GDYVtO3O7M8zO9YvEYslDqWD7B2fl3DC7v2nrUwwTk1L0GrV7mXO7idXPoqeEMbR9MZ0xiQr5q9mewdpvJv1JGKaULcVxkIFTxs2gGfaWGUS+YAZpNonlnWyEbBqx0WuDQa1VGxrWBbJhcQOEeuWLycuuDzLuXzHS77ZKWStx0jIIPwUXLdirbhZqUMWZo18Y67MAB3xFTE27pv+vBt8Vmr2tKT6GINxDTap7wWkhzfERp`;

private RSAKeyInfo backendPrivKeyInfo;

static this()
{
	backendPrivKeyInfo = RSA.decodeKey(backendPrivKey);
}


final class PlayerConnection: ProtocolConnection!BackendProtocol
{
	private
	{
		Player m_player;
		bool m_simulatorFlow;
	}

	@property Player player() { return m_player; }
	@property void player(Player rhs) { m_player = rhs; }

	@property bool simulatorFlow() const { return m_simulatorFlow; }

	this(Socket sock)
	{
		super(sock);
		setHandler(&h_serverStatus);
		setHandler(&h_loginReq);
		setHandler(&h_entityDbReq);
		setHandler(&h_spawnReq);
		setHandler(&h_throttleReq);
		setHandler(&h_courseReq);
		setHandler(&h_reconnectReq);
		setHandler(&h_listenDirReq);
		setHandler(&h_emitPingReq);
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
			m_player = Globals.players.authorizeConnection(this,
				decrypt(req.username, &backendPrivKeyInfo),
				decrypt(req.password, &backendPrivKeyInfo));
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