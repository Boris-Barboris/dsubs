module dsubs_server.player2;

import core.atomic;

import dsubs_server.common;
import dsubs_server.rng;
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
		vec2d coordRot;
		usecs_t timeShift;

		PlayerConnection m_connection;
		Submarine m_submarine;

		enum double MAX_COORD_SHIFT = 50_000.0;
		enum long MAX_TIME_SHIFT = 200_000_000L;
	}

	this(PlayerConnection con, string uname, string pw)
	{
		assert(con);
		enforce!AuthException(uname.length > 0, "empty username");
		m_username = uname;
		m_password = pw;
		m_connection = con;
		// generate random reference frame shift
		coordShift = vec2d(
			uniform(-MAX_COORD_SHIFT, MAX_COORD_SHIFT),
			uniform(-MAX_COORD_SHIFT, MAX_COORD_SHIFT));
		coordRot = uniform(-PI, PI);
		timeShift = uniform(-MAX_TIME_SHIFT, MAX_TIME_SHIFT);
	}

	@property string username() const { return m_username; }
	@property Submarine submarine() { return m_submarine; }

	/// handle connection being closed - clear m_connection field
	void onConnectionClose(PlayerConnection oldCon)
	{
		cas(&m_connection, oldCon, null);
	}

	/// force close the connection
	void closeConnection()
	{
		PlayerConnection con = atomicLoad(m_connection);
		if (con)
		{
			info("Closing previous connection of ", m_username);
			con.close();
		}
	}

	/// set current
	private void emplaceConnection(PlayerConnection con)
	{
		closeConnection();
		atomicStore(m_connection, con);
	}

	/// true if proposed credentials are the same as used
	private bool compareCredentials(string uname, string pw) const
	{
		return uname == m_username && pw == m_password;
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
					"invalid password for existing player");
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
}