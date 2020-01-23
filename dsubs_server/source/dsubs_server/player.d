module dsubs_server.player;

import std.algorithm.iteration;
import std.array: array;
import std.string: strip;

import core.atomic;

import dsubs_common.math;
import dsubs_common.event;
import dsubs_common.api.protocols.backend;
import dsubs_common.api.entities: KinematicSnapshot;

import dsubs_server.common;
import dsubs_server.connections.playercon: PlayerConnection;
import dsubs_server.connections.database;
import dsubs_server.submarine: Submarine;
import dsubs_server.dynamics: AttachedWire, RigidBody, WirePoint;
import dsubs_server.weaponry;
import dsubs_server.ai.captain: ContactRelation;


class AuthException: Exception
{
	mixin ExceptionConstructors;
}


final class SideOfConflict
{
	private
	{
		string m_name;
		bool m_neutral;
	}

	this(string name, bool neutral = false)
	{
		m_name = name;
		m_neutral = neutral;
	}

	@property string name() const { return m_name; }
	@property bool neutral() const { return m_neutral; }

	ContactRelation relateTo(const SideOfConflict otherSide) const
	{
		if (otherSide is null)
			return ContactRelation.unknown;
		if (otherSide is this)
			return ContactRelation.ally;
		if (otherSide.neutral)
			return ContactRelation.neutral;
		return ContactRelation.enemy;
	}
}


class Captain
{
	protected
	{
		Submarine m_submarine;
	}

	private SideOfConflict m_side;

	final @property SideOfConflict side() { return m_side; }
	@property void side(SideOfConflict rhs) { m_side = rhs; }

	abstract @property string name() const;
	final @property Submarine submarine() { return m_submarine; }
	@property void submarine(Submarine rhs)
	{
		if (m_submarine !is rhs)
			unsetSubmarine(m_submarine);
		m_submarine = rhs;
	}

	/// Set submarine to null. simMut.writer must be held.
	bool unsetSubmarine(Submarine assumedOldSub)
	{
		if (m_submarine is assumedOldSub)
		{
			m_submarine = null;
			return true;
		}
		return false;
	}
}


final class Player: Captain
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

		enum double MAX_COORD_SHIFT = 100_000.0;
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
		side = new SideOfConflict("Side of player " ~ uname, false);
		con.onClose += (cast(con.onClose.HandlerType) &onConnectionClose);
		con.player = this;
		atomicOp!"+="(s_playerCount, 1);
	}

	override @property string name() const { return m_username; }
	@property string username() const { return m_username; }
	@property PlayerConnection connection() { return m_connection; }

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
							h.shouldBeActive = false;
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
				if (m_submarine.dead)
					throw new Exception("submarine is dead");
				foreach (h; m_submarine.hydrophones)
					h.shouldBeActive = true;
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
		Submarine s = m_submarine;
		enforce(s, "user has no submarine, unable to generate ReconnectStateRes");
		ReconnectStateRes recState = ReconnectStateRes(
			s.spawnId, s.prototypeName, s.propulsor.prototypeName,
			genSubSnapshot(), genSubWireSnapshots(),
			s.targetCourse + coordRot, s.targetThrottle,
			s.hydrophones.map!(
				h => float(h.listenDir + coordRot)).array,
			s.rigidBody.wires.map!(w => w.desiredLength).array,
			s.tubeRange.map!(t => t.fullState).array,
			s.ammoRoomRange.map!(r => r.fullState).array
			);
		if (Globals.scenario)
		{
			Globals.scenario.generateBriefing(this, recState.mapElements, recState.briefing);
		}
		return cast(immutable) recState;
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
				randomizePosition(req, s);
				foreach (h; s.hydrophones)
				{
					h.shouldBeActive = true;
					h.listenDir = -coordRot;
				}
				s.register();
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
			if (s.dead)
				return;
			s.targetThrottle = req.target;
		}
	}

	void handleCourseRequest(const CourseReq req)
	{
		synchronized(Globals.simMut.reader)
		{
			Submarine s = m_submarine;
			enforce(s, "player has no submarine, unable to set course");
			if (s.dead)
				return;
			s.targetCourse = req.target - coordRot;
		}
	}

	void handleListenDirRequest(const ListenDirReq req)
	{
		synchronized(Globals.simMut.reader)
		{
			Submarine s = m_submarine;
			enforce(s, "player has no submarine, unable to listenDir");
			if (s.dead)
				return;
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
			if (s.dead)
				return;
			enforce(req.sonarIdx == 0, "no such sonar");
			if (Globals.sim.worldTime - m_lastPingEmit >= 5_000_000)
			{
				auto ping = s.sonar.startPing(req.ilevel);
				if (ping)
				{
					Globals.acous.registerSource(ping);
					m_lastPingEmit = Globals.sim.worldTime;
				}
			}
		}
	}

	void handleLoadTubeReq(const LoadTubeReq req)
	{
		synchronized(Globals.simMut.reader)
		{
			Submarine s = m_submarine;
			enforce(s, "player has no submarine, unable to EmitPingReq");
			if (s.dead)
				return;
			Tube tube = s.getTube(req.tubeId);
			TubeOperationResult topRes = tube.processLoadRequest(req.weaponName);
			PlayerConnection con = m_connection;
			if (con && topRes.tubeChanged)
				con.sendMessage(cast(immutable) TubeStateUpdateRes(tube.fullState));
			if (con && topRes.roomChanged)
				con.sendMessage(cast(immutable) AmmoRoomStateUpdateRes(tube.room.fullState));
		}
	}

	void handleSetTubeStateReq(const SetTubeStateReq req)
	{
		synchronized(Globals.simMut.reader)
		{
			Submarine s = m_submarine;
			enforce(s, "player has no submarine, unable to EmitPingReq");
			if (s.dead)
				return;
			Tube tube = s.getTube(req.tubeId);
			TubeOperationResult topRes = tube.processStateRequest(req.desiredState);
			PlayerConnection con = m_connection;
			if (con && topRes.tubeChanged)
				con.sendMessage(immutable TubeStateUpdateRes(tube.fullState));
			assert(!topRes.roomChanged);
		}
	}

	void handleWireDesiredLengthReq(WireDesiredLengthReq req)
	{
		synchronized(Globals.simMut.reader)
		{
			Submarine s = m_submarine;
			enforce(s, "player has no submarine, unable to WireDesiredLengthReq");
			if (s.dead)
				return;
			enforce(req.wireIdx >= 0 && req.wireIdx < s.rigidBody.wires.length,
				"invalid wire index");
			s.rigidBody.wires[req.wireIdx].desiredLength = req.desiredLength;
		}
	}

	void handleLaunchTubeReq(LaunchTubeReq req)
	{
		synchronized(Globals.simMut.reader)
		{
			Submarine s = m_submarine;
			enforce(s, "player has no submarine, unable to EmitPingReq");
			if (s.dead)
				return;
			Tube tube = s.getTube(req.tubeId);
			// reference frame translation for courses
			foreach (ref WeaponParamValue param; req.weaponParams)
			{
				if (param.type == WeaponParamType.marchCourse ||
					param.type == WeaponParamType.activeCourse)
				{
					param.course = param.course - coordRot;
				}
			}
			TubeOperationResult topRes = tube.processLaunchRequest(
				req.weaponName, req.weaponParams);
			PlayerConnection con = m_connection;
			if (con && topRes.tubeChanged)
				con.sendMessage(immutable TubeStateUpdateRes(tube.fullState));
			assert(!topRes.roomChanged);
		}
	}

	private KinematicSnapshot genSubSnapshot()
	{
		assert(m_submarine);
		Submarine s = m_submarine;
		vec2d shiftedPos = posToClientSpace(s.transform.wposition);
		double shiftedRot = rotToClientSpace(s.transform.wrotation);
		vec2d vel = dirToClientSpace(s.rigidBody.kinet.vel);
		double angVel = s.rigidBody.kinet.angVel;
		return KinematicSnapshot(
				Globals.sim.worldTime + timeShift,
				vec2d(shiftedPos.x, shiftedPos.y),
				vec2d(vel.x, vel.y),
				shiftedRot,
				angVel);
	}

	private WireSnapshot[] genSubWireSnapshots()
	{
		assert(m_submarine);
		Submarine s = m_submarine;
		WireSnapshot[] res;
		for (size_t i = 0; i < s.rigidBody.wires.length; i++)
		{
			AttachedWire wire = s.rigidBody.wires[i];
			WireSnapshot wireSnap;
			wireSnap.atTime = Globals.sim.worldTime + timeShift;
			wireSnap.points.length = wire.points.length;
			wireSnap.attachPosition = posToClientSpace(wire.attachTransform.wposition);
			foreach (j, point; wire.points)
			{
				wireSnap.points[j].position = (posToClientSpace(point.pos) - wireSnap.attachPosition).to!vec2f;
				wireSnap.points[j].velocity = dirToClientSpace(point.vel).to!vec2f;
			}
			res ~= wireSnap;
		}
		return res;
	}

	vec2d posToClientSpace(vec2d pos) const
	{
		return rotateVector(pos - coordShift, coordRot);
	}

	vec2d dirToClientSpace(vec2d dir) const
	{
		return rotateVector(dir, coordRot);
	}

	double rotToClientSpace(double rot) const
	{
		return rot + coordRot;
	}

	@property bool hasAliveSub() const
	{
		const Submarine sub = m_submarine;
		return (sub && !sub.dead);
	}

	// simMut.writer is held by the simulator
	void sendUpdate()
	{
		Submarine s = m_submarine;
		PlayerConnection con = m_connection;

		// handle death
		if (s && s.dead)
			m_submarine = null;

		if (con && con.isOpen && con.simulatorFlow && s)
		{
			if (s.dead)
			{
				con.simulatorFlow = false;
				con.sendMessage(immutable DeathRes(s.causeOfDeath, ""));
				return;
			}
			con.sendMessage(cast(immutable) SubKinematicRes(genSubSnapshot(),
				genSubWireSnapshots()));
			immutable(HydrophoneData)[] hdata;
			immutable(HydrophoneAudio)[] haudio;
			foreach (i, h; s.hydrophones)
			{
				if (!h.active)
					continue;
				HydrophoneData hd;
				hd.hydrophoneIdx = i.to!int;
				hd.position = posToClientSpace(h.transform.wposition);
				hd.rotation = rotToClientSpace(h.transform.wrotation);
				for (int j = 0; j < h.antennaCount; j++)
					hd.antennaes ~= AntennaeData(j, h.getBroadbandData(j));
				hdata ~= cast(immutable) hd;
				if (h.listenDirValid)
				{
					int srate;
					auto samples = h.pcb;
					// trace("samples start: ", samples[0..10], " end: ", samples[$-10..$]);
					haudio ~= immutable HydrophoneAudio(i.to!int, rotToClientSpace(h.listenDir),
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
			// now send updates about tubes and rooms
			bool[int] updatedRooms;
			foreach (const Tube tube; s.tubeRange)
			{
				if (tube.lastSimUpdateResult.tubeChanged)
					con.sendMessage(cast(immutable) TubeStateUpdateRes(tube.fullState));
				if (tube.lastSimUpdateResult.roomChanged)
					updatedRooms[tube.room.id] = true;
			}
			foreach (int roomId; updatedRooms.byKey)
				con.sendMessage(cast(immutable) AmmoRoomStateUpdateRes(
					s.getAmmoRoom(roomId).fullState));
		}
	}

	private void randomizePosition(const SpawnReq req, Submarine sub)
	{
		double rot;
		if (Globals.scenario)
		{
			vec2d pos;
			Globals.scenario.selectPlayerSpawnPosition(this, req, pos, rot);
			sub.transform.position = pos;
		}
		else
		{
			double px = uniform(-1000.0, 1000.0);
			double py = uniform(-1000.0, 1000.0);
			rot = uniform(-PI, PI);
			sub.transform.position = vec2d(px, py);
		}
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

	@property Player[string] players() { return m_players; }

	/// Get or create Player for connection.
	Player authorizeConnection(PlayerConnection con, string username, string password)
	{
		assert(con);
		username = strip(username);
		if (username.length == 0)
			throw new AuthException("Empty login");
		scope(success) info("Player ", username, " authorized");
		if (Globals.database)
		{
			PlayerDb* pdb = Globals.database.getPlayerByLogin(username);
			if (pdb is null)
				Globals.database.insertPlayer(username, password);
			else if (pdb.login_password != password)
				throw new AuthException("invalid login or password");
		}
		synchronized(Globals.simMut.reader)
		{
			synchronized(this)
			{
				Player* p = username in m_players;
				if (p !is null)
				{
					// player is already present, let's try to authorize new connection
					enforce!AuthException(p.compareCredentials(username, password),
						"invalid login or password");
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

	/// Run dlg on each player in parallel.
	void forEachPlayer(scope void delegate(Player) dlg)
	{
		foreach (Player p; Globals.taskPool.parallel(m_players.values, 1))
			dlg(p);
	}

	/// Run dlg on each player with active connection and alive submarine, in
	/// parallel.
	void forEachAliveConnectedPlayer(scope void delegate(
		Player p, Submarine s, PlayerConnection pcon) dlg)
	{
		foreach (Player p; Globals.taskPool.parallel(m_players.values, 1))
		{
			Submarine sub = p.submarine;
			PlayerConnection pcon = p.connection;
			if (sub !is null && !sub.dead && pcon !is null)
				dlg(p, sub, pcon);
		}
	}
}