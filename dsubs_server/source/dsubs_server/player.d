module dsubs_server.player;

import core.atomic;

import dsubs_common.math;
import dsubs_common.api.protocols.backend;
import dsubs_common.api.entities: KinematicSnapshot;

import dsubs_server.common;
import dsubs_server.connections.playercon: PlayerConnection;
import dsubs_server.submarine: Submarine;


class AuthException: Exception
{
	mixin ExceptionConstructors;
}


final class Player
{
	private
	{
		const string m_username;
		const string m_password;

		vec2d coordShift;
		double coordRot;
		usecs_t timeShift;

		PlayerConnection m_connection;
		Submarine m_submarine;

		enum double MAX_COORD_SHIFT = 50_000.0;
		enum long MAX_TIME_SHIFT = 200_000_000L;

		static shared int s_playerCount = 0;
	}

	static int getPlayersOnline()
	{
		return atomicLoad(s_playerCount);
	}

	this(PlayerConnection con, string uname, string pw)
	{
		assert(con);
		enforce!AuthException(uname.length > 0, "empty username");
		m_username = uname;
		m_password = pw;
		m_connection = con;
		con.onClose += (cast(con.onClose.HandlerType) &onConnectionClose);
		con.player = this;
		atomicOp!"+="(s_playerCount, 1);
	}

	@property string username() const { return m_username; }
	@property Submarine submarine() { return m_submarine; }

	/// Set submarine to null. simMut should be held.
	bool unsetSubmarine(Submarine assumedOldSub)
	{
		if (m_submarine is assumedOldSub)
		{
			m_submarine = null;
			return true;
		}
		return false;
	}

	private void generateShift()
	{
		// generate random reference frame shift
		coordShift = vec2d(
			uniform(-MAX_COORD_SHIFT, MAX_COORD_SHIFT),
			uniform(-MAX_COORD_SHIFT, MAX_COORD_SHIFT));
		coordRot = uniform(-PI, PI);
		timeShift = uniform(-MAX_TIME_SHIFT, MAX_TIME_SHIFT);
	}

	/// handle connection being closed.
	private void onConnectionClose(PlayerConnection oldCon)
	{
		assert(oldCon && !oldCon.isOpen);
		oldCon.player = null;
		synchronized(this)
		{
			if (m_connection is oldCon)
			{
				m_connection = null;
				atomicOp!"-="(s_playerCount, 1);
			}
		}
	}

	/// force close the connection
	bool closeConnection()
	{
		PlayerConnection con = m_connection;
		if (con)
		{
			info("Closing previous connection of ", m_username);
			con.close();
			return true;
		}
		return false;
	}

	/// set current
	private void emplaceConnection(PlayerConnection con)
	{
		synchronized(this)
		{
			closeConnection();
			m_connection = con;
			atomicOp!"+="(s_playerCount, 1);
			con.onClose += (cast(con.onClose.HandlerType) &onConnectionClose);
		}
	}

	/// true if proposed credentials are the same as used
	private bool compareCredentials(string uname, string pw) const
	{
		return uname == m_username && pw == m_password;
	}

	immutable(ReconnectStateRes) getReconnectState() const
	{
		const Submarine s = m_submarine;
		enforce(s, "user has no submarine, unable to generate ReconnectStateRes");
		return immutable ReconnectStateRes(
			s.spawnId, s.prototypeName, s.propulsor.prototypeName,
			s.targetCourse + coordRot, s.targetThrottle);
	}

	void handleSpawnRequest(const SpawnReq req)
	{
		synchronized(Globals.simMut.reader)
		{
			synchronized(this)
			{
				Submarine s = m_submarine;
				enforce(s is null, "Already spawned");
				s = Globals.entityDb.buildSubFromLoadout(req, this);
				generateShift();
				randomizePosition(s);
				s.bootstrap();
				m_submarine = s;
			}
		}
	}

	void handleThrottleRequest(const ThrottleReq req)
	{
		synchronized(Globals.simMut.reader)
		{
			Submarine s = m_submarine;
			enforce(s, "player has no submarine, unable to set throttle");
			s.targetThrottle = req.target;
		}
	}

	void handleCourseRequest(const CourseReq req)
	{
		synchronized(Globals.simMut.reader)
		{
			Submarine s = m_submarine;
			enforce(s, "player has no submarine, unable to set course");
			s.targetCourse = req.target + coordRot;
		}
	}

	// simMut.writer is held by the simulator
	void sendKinematicsUpdate(usecs_t worldTime)
	{
		Submarine s = m_submarine;
		PlayerConnection con = m_connection;
		if (con && con.isOpen && s)
		{
			vec2d shiftedPos = rotateVector(s.transform.position - coordShift, coordRot);
			double shiftedRot = s.transform.rotation + coordRot;
			vec2d vel = rotateVector(s.rigidBody.kinet.vel, coordRot);
			double angVel = s.rigidBody.kinet.angVel;
			immutable(SubKinematicRes) msg = immutable SubKinematicRes(
				KinematicSnapshot(
					worldTime + timeShift,
					Vector2d(shiftedPos.x, shiftedPos.y),
					Vector2d(vel.x, vel.y),
					shiftedRot,
					angVel));
			con.sendMessage(msg);
		}
	}

	private static void randomizePosition(Submarine sub)
	{
		double px = uniform(-1000.0, 1000.0);
		double py = uniform(-1000.0, 1000.0);
		double rot = uniform(-PI, PI);
		sub.transform.position = vec2d(px, py);
		sub.transform.rotation = rot;
		sub.rigidBody.updateFromTransform();
		sub.rudder.targetCourse = rot;
	}
}


final class PlayerCollection
{
	private
	{
		Player[string] m_players;
	}

	/// Get or create Player for connection.
	Player authorizeConnection(PlayerConnection con, string username, string password)
	{
		assert(con);
		scope(success) info("Player ", username, " authorized");
		synchronized(this)
		{
			Player* p = username in m_players;
			if (p !is null)
			{
				// player is already present, let's try to authorize new connection
				enforce!AuthException(p.compareCredentials(username, password),
					"invalid password");
				p.emplaceConnection(con);
				return *p;
			}
			else
			{
				// new player
				Player np = new Player(con, username, password);
				m_players[username] = np;
				return np;
			}
		}
	}

	/// Run dlg on each player while holding a lock on
	/// player collection.
	void forEachPlayer(scope void delegate(Player) dlg)
	{
		synchronized (this)
		{
			foreach (Player p; m_players.values)
				dlg(p);
		}
	}
}