module dsubs_server.connections.playercon;

import std.socket;

import core.atomic;

import dsubs_common.api;
import dsubs_common.api.protocols.backend;
import dsubs_common.network.connection;

import dsubs_server.common;
import dsubs_server.player;


final class PlayerConnection: ProtocolConnection!BackendProtocol
{
	private
	{
		Player m_player;
	}

	@property Player player() { return m_player; }
	@property void player(Player rhs) { m_player = rhs; }

	this(Socket sock)
	{
		super(sock);
		setHandler(&h_serverStatus);
		setHandler(&h_loginReq);
		setHandler(&h_entityDbReq);
		setHandler(&h_spawnReq);
		setHandler(&h_throttleReq);
		setHandler(&h_courseReq);
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
			m_player = Globals.players.authorizeConnection(this, req.username, req.password);
			if (m_player.submarine)
			{
				// we are already spawned
				sendMessage(immutable LoginRes(true, "Welcome",
					Globals.entityDb.commonEntityDbHash, true));
				sendMessage(m_player.getReconnectState());
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
		p.handleSpawnRequest(req);
		sendMessage(immutable SpawnRes(true));
	}

	void h_throttleReq(ThrottleReq req)
	{
		Player p = m_player;
		enforce!AuthException(p, "unauthorized");
		p.handleThrottleRequest(req);
	}

	void h_courseReq(CourseReq req)
	{
		Player p = m_player;
		enforce!AuthException(p, "unauthorized");
		p.handleCourseRequest(req);
	}
}