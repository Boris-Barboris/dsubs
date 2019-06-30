module dsubs_server.player;

import std.algorithm.iteration;
import std.array: array;

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
		usecs_t m_lastPingEmit = ulong.min;

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

	/// Set submarine to null. simMut must be held.
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
		synchronized(Globals.simMut.reader)
		{
			synchronized(this)
			{
				if (m_connection is oldCon)
				{
					if (m_submarine)
					{
						foreach (h; m_submarine.hydrophones)
							h.active = false;
						m_submarine.sonar.active = false;
					}
					m_connection = null;
					atomicOp!"-="(s_playerCount, 1);
				}
			}
		}
	}

	/// force close the connection
	private bool closeConnection()
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
			if (m_submarine)
			{
				foreach (h; m_submarine.hydrophones)
					h.active = true;
				m_submarine.sonar.active = true;
			}
		}
	}

	/// true if proposed credentials are the same as used
	private bool compareCredentials(string uname, string pw) const
	{
		return uname == m_username && pw == m_password;
	}

	immutable(ReconnectStateRes) getReconnectState()
	{
		const Submarine s = m_submarine;
		enforce(s, "user has no submarine, unable to generate ReconnectStateRes");
		return immutable ReconnectStateRes(
			s.spawnId, s.prototypeName, s.propulsor.prototypeName,
			genSubSnapshot(), s.targetCourse + coordRot, s.targetThrottle,
			cast(immutable(float)[]) s.hydrophones.map!(
				h => float(h.listenDir + coordRot)).array
			);
	}

	immutable(ReconnectStateRes) handleSpawnRequest(const SpawnReq req)
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

				s.transform.rotation = dgr2rad(180);
				s.rudder.targetCourse = dgr2rad(180);

				m_submarine = s;
				foreach (h; s.hydrophones)
				{
					h.active = true;
					h.listenDir = -coordRot;
				}
				s.register();

				// test minoga running at you
				import dsubs_server.torpedo;

				const TorpedoFactory tf = Globals.entityDb.getTorpedoFactory("Minoga");
				WeaponParamValue[] pvs;
				WeaponParamValue pv;

				pv.type = WeaponParamType.marchCourse;
				pv.course = dgr2rad(0.0);
				pvs ~= pv;
				pv.type = WeaponParamType.activeCourse;
				pv.course = dgr2rad(0.0);
				pvs ~= pv;
				pv.type = WeaponParamType.activationRange;
				pv.range = 200.0f;
				pvs ~= pv;
				pv.type = WeaponParamType.activeSpeed;
				pv.speed = 29.0f;
				pvs ~= pv;
				pv.type = WeaponParamType.searchPattern;
				pv.searchPattern = WeaponSearchPattern.snake;
				pvs ~= pv;

				Torpedo t = tf.build(null, pvs);
				t.transform.position = s.transform.wposition + vec2d(0, -1400);
				t.register();

				return getReconnectState();
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
			s.targetCourse = req.target - coordRot;
		}
	}

	void handleListenDirRequest(const ListenDirReq req)
	{
		synchronized(Globals.simMut.reader)
		{
			Submarine s = m_submarine;
			enforce(s, "player has no submarine, unable to listenDir");
			int hcount = s.hydrophones.length.to!int;
			enforce(req.hydrophoneIdx >= 0 && req.hydrophoneIdx < hcount, "no such hydrophone");
			s.hydrophones[req.hydrophoneIdx].listenDir = req.dir - coordRot;
		}
	}

	void handleEmitPingRequest(const EmitPingReq req)
	{
		synchronized(Globals.simMut.reader)
		{
			Submarine s = m_submarine;
			enforce(s, "player has no submarine, unable to EmitPingReq");
			enforce(req.sonarIdx == 0, "no such sonar");
			if (Globals.sim.worldTime - m_lastPingEmit >= 5_000_000)
			{
				auto ping = s.sonar.startPing(req.ilevel);
				if (ping)
				{
					Globals.acous.registerPing(ping);
					m_lastPingEmit = Globals.sim.worldTime;
				}
			}
		}
	}

	private KinematicSnapshot genSubSnapshot()
	{
		assert(m_submarine);
		Submarine s = m_submarine;
		vec2d shiftedPos = rotateVector(s.transform.wposition - coordShift, coordRot);
		double shiftedRot = s.transform.wrotation + coordRot;
		vec2d vel = rotateVector(s.rigidBody.kinet.vel, coordRot);
		double angVel = s.rigidBody.kinet.angVel;
		return KinematicSnapshot(
				Globals.sim.worldTime + timeShift,
				vec2d(shiftedPos.x, shiftedPos.y),
				vec2d(vel.x, vel.y),
				shiftedRot,
				angVel);
	}

	// simMut.writer is held by the simulator
	void sendUpdate()
	{
		Submarine s = m_submarine;
		PlayerConnection con = m_connection;
		if (con && con.isOpen && con.simulatorFlow && s)
		{
			con.sendMessage(immutable SubKinematicRes(genSubSnapshot()));
			immutable(HydrophoneData)[] hdata;
			foreach (i, const h; s.hydrophones)
			{
				HydrophoneData hd;
				hd.hydrophoneIdx = i.to!int;
				for (int j = 0; j < h.antennaCount; j++)
					hd.antennaes ~= AntennaeData(j, h.getBroadbandData(j));
				hdata ~= cast(immutable) hd;
			}
			immutable(HydrophoneAudio)[] haudio;
			foreach (i, h; s.hydrophones)
			{
				if (h.listenDirValid)
				{
					int srate;
					auto samples = h.pcb;
					trace("samples start: ", samples[0..10], " end: ", samples[$-10..$]);
					haudio ~= immutable HydrophoneAudio(i.to!int, h.listenDir + coordRot,
						samples, samples.length.to!int);
				}
			}
			con.sendMessage(immutable AcousticStreamRes(
				Globals.sim.worldTime + timeShift, hdata, haudio));
			// now active sonar
			if (s.sonar.active && s.sonar.hasSliceToSend)
			{
				immutable SonarSliceData sdata = immutable SonarSliceData(
					0, s.sonar.pingCounter, s.sonar.readySliceId,
					s.sonar.getLastSlice());
				con.sendMessage(immutable SonarStreamRes(
					Globals.sim.worldTime + timeShift, [sdata]));
				s.sonar.markSliceSent();
			}
		}
	}

	private static void randomizePosition(Submarine sub)
	{
		double px = uniform(-1000.0, 1000.0);
		double py = uniform(-1000.0, 1000.0);
		double rot = uniform(-PI, PI);
		sub.transform.position = vec2d(px, py);
		sub.transform.rotation = rot;
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
		synchronized(Globals.simMut.reader)
		{
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
	}

	/// Run dlg on each player while holding a lock on
	/// player collection.
	void forEachPlayer(scope void delegate(Player) dlg)
	{
		synchronized (this)
		{
			foreach (Player p; Globals.taskPool.parallel(m_players.values, 2))
				dlg(p);
		}
	}
}