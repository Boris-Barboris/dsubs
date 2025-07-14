/*
DSubs
Copyright (C) 2017-2025 Baranin Alexander

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
module dsubs_server.player;

import std.algorithm.iteration;
import std.array: array;
import std.string: strip;
import std.uuid;

import core.atomic;

import dsubs_common.math;
import dsubs_common.event;
import dsubs_common.api.messages;
import dsubs_common.api.entities: KinematicSnapshot;

import dsubs_server.common;
import dsubs_server.connections.playercon: PlayerConnection;
import dsubs_server.connections.database;
import dsubs_server.submarine: Submarine;
import dsubs_server.email;
import dsubs_server.dynamics: AttachedWire, RigidBody, WirePoint;
import dsubs_server.vessel: KillRecord;
import dsubs_server.weaponry;
import dsubs_server.torpedo;
import dsubs_server.scenario: Scenario;
import dsubs_server.simulator: Simulator;
import dsubs_server.ai.aicaptain: ContactRelation;


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
		// captain has at most one submarine
		Submarine m_submarine;
	}

	private SideOfConflict m_side;
	private UUID m_id;

	this()
	{
		m_id = randomUUID();
	}

	final @property SideOfConflict side() { return m_side; }
	@property void side(SideOfConflict rhs) { m_side = rhs; }

	abstract @property string name() const;

	final @property UUID id() const { return m_id; }

	final @property Submarine submarine()
	{
		// atomics because simulator-player-playerconnection concurrency
		// relies on atomic m_submarine pointer update. See player_threads.pml
		// model for the high-level algorithm abstraction.
		return atomicLoad(m_submarine);
	}
	@property void submarine(Submarine rhs)
	{
		atomicStore(m_submarine, rhs);
	}

	/// Set submarine to null, if it's currently equal to assumedOldSub.
	bool unsetSubmarine(Submarine assumedOldSub)
	{
		return cas(&m_submarine, assumedOldSub, null);
	}
}

/*
In-memory representation of a human player captain, that can be authorized.
Acts as a bridge between connection and player's submarine, translates and
issues messages and updates, implements reference frame translation.
*/
final class Player: Captain
{
	private
	{
		// cleartext
		const string m_username;
		const string m_password;

		vec2d coordShift;
		double coordRot;
		usecs_t timeShift;

		// used to rate-limit ping requests
		usecs_t m_lastPingEmit = -6_000_000L;

		// There is at most one "active" connection that
		// receives updates from the server.
		// Always changed under "this" lock.
		PlayerConnection m_connection;

		enum double MAX_COORD_SHIFT = 100_000.0;
		enum long MAX_TIME_SHIFT = 200_000_000L;

		/// number of players with active connections
		static shared int s_playerCount = 0;
	}

	@property bool isDeveloper() const
	{
		return m_username == "Boris-Barboris" || m_username == "Boris-Barboris2" ||
			Globals.database is null;
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
		con.player = this;
		con.onClose += (cast(con.onClose.HandlerType) &onConnectionClose);
		atomicOp!"+="(s_playerCount, 1);
	}

	override @property string name() const { return m_username; }
	@property string username() const { return m_username; }
	@property inout(PlayerConnection) connection() inout { return m_connection; }

	/// generate random reference frame shift
	private void generateShift()
	{
		coordShift = vec2d(
			uniform(-MAX_COORD_SHIFT, MAX_COORD_SHIFT),
			uniform(-MAX_COORD_SHIFT, MAX_COORD_SHIFT));
		coordRot = uniform(-PI, PI);
		timeShift = uniform(-MAX_TIME_SHIFT, MAX_TIME_SHIFT);
	}

	private void resetShiftToZero()
	{
		coordShift = vec2d(0.0, 0.0);
		coordRot = 0.0;
		timeShift = 0;
	}

	/// Called from connection's reader thread when connection is closed.
	private void onConnectionClose(PlayerConnection oldCon)
	{
		assert(oldCon && !oldCon.isOpen);
		oldCon.player = null;
		synchronized(this)
		{
			atomicOp!"-="(s_playerCount, 1);
			Submarine sub = oldCon.simFlowSub;
			// if there is a submarine we deactivate it's sensors
			// to save computational resources.
			if (sub)
			{
				synchronized(sub.simulator.simMut.reader)
				{
					// every connection has to do decrease refcount for it's sub
					sub.decSubConRefCounter();
					oldCon.simFlowSub = null;
					oldCon.simulatorFlow = false;
					// if there is no new connection that replaced the old one...
					if (m_connection is oldCon)
					{
						// disable sensors to optimize simulator
						foreach (h; sub.hydrophones)
							h.shouldBeActive = false;
						sub.sonar.active = false;
					}
				}
				// onConnectionClose may be called very late, way after
				// m_submarine has changed. We need to lock on current simulator to
				// change m_connection, not on the sim of oldCon.simFlowSub.
				Submarine currentSub = submarine;
				if (currentSub)
				{
					synchronized(currentSub.simulator.simMut.reader)
					{
						if (m_connection is oldCon)
							m_connection = null;
					}
				}
				else
				{
					if (m_connection is oldCon)
						m_connection = null;
				}
			}
			else
			{
				if (m_connection is oldCon)
					m_connection = null;
			}
			// locking can be lax with secondaryConnection
			if (oldCon.secondaryConnection)
				oldCon.secondaryConnection.close();
		}
	}

	/// force close the connection. Returns old connection.
	private PlayerConnection closeConnection()
	{
		PlayerConnection con = m_connection;
		if (con)
		{
			info("Evicting previous connection of ", m_username);
			con.close();
			PlayerConnection secCon = con.secondaryConnection;
			if (secCon)
				secCon.close();
			return con;
		}
		return null;
	}

	static void enableSubSensors(Submarine sub)
	{
		foreach (h; sub.hydrophones)
			h.shouldBeActive = true;
		sub.sonar.active = true;
	}

	/// Set current m_connection to new value. Returns old connection (if there was).
	private PlayerConnection emplaceConnection(PlayerConnection con)
	{
		synchronized(this)
		{
			PlayerConnection res = closeConnection();
			atomicOp!"+="(s_playerCount, 1);
			con.onClose += (cast(con.onClose.HandlerType) &onConnectionClose);
			Submarine sub = submarine;
			if (sub)
			{
				synchronized(sub.simulator.simMut.reader)
				{
					if (sub.dead || sub.simulator.finished)
					{
						trace("Emplacing connection while the sub/sim is dead");
						unsetSubmarine(sub);
					}
					m_connection = con;		// important, check spin model.
				}
			}
			else
				m_connection = con;
			return res;
		}
	}

	/// Closes and returns the old secondary connection (if there was one).
	private PlayerConnection emplaceSecondaryConnection(PlayerConnection con)
	{
		synchronized(this)
		{
			enforce(m_connection, "Player has no primary connection");
			Submarine sub = submarine;
			if (sub)
			{
				synchronized(sub.simulator.simMut.reader)
				{
					assert(m_connection);
					PlayerConnection oldSecCon = m_connection.secondaryConnection;
					m_connection.secondaryConnection = con;
					if (oldSecCon)
						oldSecCon.close();
					return oldSecCon;
				}
			}
			else
			{
				PlayerConnection oldSecCon = m_connection.secondaryConnection;
				m_connection.secondaryConnection = con;
				if (oldSecCon)
					oldSecCon.close();
				return oldSecCon;
			}
		}
	}

	/// true if proposed credentials are the same as used
	private bool areCredentialsEqual(string uname, string pw) const
	{
		return uname == m_username && pw == m_password;
	}

	// sim's lock must be held.
	immutable(ReconnectStateRes) getReconnectState()
	{
		Submarine s = submarine;
		enforce(s, "user has no submarine, unable to generate ReconnectStateRes");
		enforce(!s.dead, "user has a submarine, but it is dead");
		ReconnectStateRes recState = ReconnectStateRes(
			s.id.toString(), s.simulator.id, s.prototypeName,
			s.propulsors[0].prototypeName,
			genSubSnapshot(s), genSubWireSnapshots(s),
			s.targetCourse + coordRot, s.targetThrottle,
			s.hydrophones.map!(
				h => float(h.listenDir + coordRot)).array,
			s.rigidBody.wires.map!(w => w.desiredLength).array,
			s.tubeRange.map!(t => t.fullState).array,
			s.tubeRange.filter!(t => t.wireGuidanceActive).map!(t =>
				t.wireGuidedWeapon.guidance.getFullState(true)).array,
			s.ammoRoomRange.map!(r => r.fullState).array
			);
		// space transform
		foreach (ref guidanceState; recState.wireGuidanceStates)
		{
			foreach (ref WeaponParamValue param; guidanceState.weaponParams)
			{
				if (param.type == WeaponParamType.course)
				{
					param.course = param.course + coordRot;
				}
			}
		}
		recState.isPaused = s.simulator.paused;
		recState.canBePaused = s.simulator.canBePaused;
		if (s.simulator.scenario)
		{
			Scenario scenario = s.simulator.scenario;
			ChatMessage briefingMsg;
			scenario.generateBriefing(
				this, recState.mapElements, recState.goals, briefingMsg);
			scenario.resetVersions(this);
			recState.lastChatLogs = [briefingMsg];
			trace(scenario.spawner.scenarioType);
			recState.canAbandon =
				scenario.spawner.scenarioType != ScenarioType.persistentSimulator;
		}
		recState.timeAccelerationFactor = s.simulator.timeAccelerationFactor;
		return cast(immutable) recState;
	}

	void handleSpawnRequest(const SpawnReq req, PlayerConnection con)
	{
		synchronized(this)
		{
			Submarine s = submarine;
			enforce(s is null, "Already spawned");
			Scenario scen = Globals.scenarioDb.generateScenarioForSpawnReq(this, req);
			if (scen.randomizeReferenceFrame)
				generateShift();
			else
				resetShiftToZero();
			m_lastPingEmit = -6_000_000L;
			// spawn submarine
			synchronized(scen.simulator.simMut.reader)
			{
				Submarine sub = Globals.entityDb.buildSubFromLoadout(req, this, true);
				// start position initialization
				vec2d pos;
				double rot;
				scen.selectPlayerSpawnPosition(this, pos, rot);
				sub.transform.position = pos;
				sub.transform.rotation = rot;
				sub.rudder.targetCourse = rot;
				foreach (h; sub.hydrophones)
				{
					h.shouldBeActive = true;
					h.listenDir = rot;
				}
				sub.register(scen.simulator);
				sub.incSubConRefCounter();
				con.simFlowSub = sub;
				con.simulatorFlow = true;
				// schedule simulator for execution
				if (req.type == SpawnRequestType.newSimulator)
					Globals.simulators.add(scen.simulator);
				con.sendMessage(getReconnectState());
			}
		}
	}

	void handleDevCreateSimulatorReq(const DevCreateSimulatorReq req)
	{
		synchronized(this)
		{
			enforce(isDeveloper, "Not a developer");
			Scenario scen = Globals.scenarioDb.generateScenarioForCreateSimulatorReq(
				this, req.scenarioName);
			// schedule simulator for execution
			Globals.simulators.add(scen.simulator);
		}
	}

	void handleThrottleRequest(const ThrottleReq req)
	{
		Submarine s = submarine;
		if (s is null)
			return;
		synchronized(s.simulator.simMut.reader)
		{
			if (s !is submarine)
				return;
			s.targetThrottle = req.target;
		}
	}

	void handleCourseRequest(const CourseReq req)
	{
		Submarine s = submarine;
		if (s is null)
			return;
		synchronized(s.simulator.simMut.reader)
		{
			if (s !is submarine)
				return;
			s.targetCourse = req.target - coordRot;
		}
	}

	void handleListenDirRequest(const ListenDirReq req)
	{
		Submarine s = submarine;
		if (s is null)
			return;
		synchronized(s.simulator.simMut.reader)
		{
			if (s !is submarine)
				return;
			int hcount = s.hydrophones.length.to!int;
			enforce(req.hydrophoneIdx >= 0 && req.hydrophoneIdx < hcount, "no such hydrophone");
			s.hydrophones[req.hydrophoneIdx].listenDir = req.dir - coordRot;
		}
	}

	void handleEmitPingRequest(const EmitPingReq req)
	{
		Submarine s = submarine;
		if (s is null)
			return;
		synchronized(s.simulator.simMut.reader)
		{
			if (s !is submarine)
				return;
			enforce(req.sonarIdx == 0, "no such sonar");
			usecs_t worldTime = s.simulator.worldTime;
			if ((worldTime - m_lastPingEmit) >= 5_000_000L)
			{
				auto ping = s.sonar.startPing(req.ilevel);
				if (ping)
				{
					s.simulator.acous.registerSource(ping);
					m_lastPingEmit = worldTime;
				}
			}
		}
	}

	void handleLoadTubeReq(const LoadTubeReq req)
	{
		Submarine s = submarine;
		if (s is null)
			return;
		synchronized(s.simulator.simMut.reader)
		{
			if (s !is submarine)
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
		Submarine s = submarine;
		if (s is null)
			return;
		synchronized(s.simulator.simMut.reader)
		{
			if (s !is submarine)
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
		Submarine s = submarine;
		if (s is null)
			return;
		synchronized(s.simulator.simMut.reader)
		{
			if (s !is submarine)
				return;
			enforce(req.wireIdx >= 0 && req.wireIdx < s.rigidBody.wires.length,
				"invalid wire index");
			s.rigidBody.wires[req.wireIdx].desiredLength = req.desiredLength;
		}
	}

	void handlePauseSimulatorReq(PauseSimulatorReq req)
	{
		Submarine s = submarine;
		Simulator sim;
		if (s is null)
		{
			sim = observedSimulator;
			if (sim is null)
				return;
		}
		else
			sim = s.simulator;
		synchronized(sim.simMut.reader)
		{
			if (s && s !is submarine)
				return;
			sim.paused = req.shouldBePaused;
		}
	}

	void handleTimeAccelerationReq(TimeAccelerationReq req)
	{
		Submarine s = submarine;
		Simulator sim;
		if (s is null)
		{
			sim = observedSimulator;
			if (sim is null)
				return;
		}
		else
			sim = s.simulator;
		if (!isDeveloper)
		{
			enforce(req.timeAccelerationFactor >= 5 && req.timeAccelerationFactor <= 80,
				"timeAccelerationFactor not in [5, 80] range");
		}
		synchronized(sim.simMut.reader)
		{
			if (s && s !is submarine)
				return;
			sim.timeAccelerationFactor = req.timeAccelerationFactor;
		}
	}

	void handleWireGuidanceUpdateParamsReq(WireGuidanceUpdateParamsReq req)
	{
		Submarine s = submarine;
		if (s is null)
			return;
		synchronized(s.simulator.simMut.reader)
		{
			if (s !is submarine)
				return;
			Weapon wpn = s.getWireGuidedWeapon(req.wireGuidanceId);
			if (wpn)
			{
				// client to world rotation transform
				foreach (ref WeaponParamValue param; req.weaponParams)
				{
					if (param.type == WeaponParamType.course)
					{
						param.course = param.course - coordRot;
					}
				}
				wpn.guidance.updateParamsByWire(req.weaponParams);
			}
		}
	}

	void handleWireGuidanceActivateReq(WireGuidanceActivateReq req)
	{
		Submarine s = submarine;
		if (s is null)
			return;
		synchronized(s.simulator.simMut.reader)
		{
			if (s !is submarine)
				return;
			Weapon wpn = s.getWireGuidedWeapon(req.wireGuidanceId);
			if (wpn)
				wpn.guidance.activateByWire(req.shouldBeActive);
		}
	}

	void handleLaunchTubeReq(LaunchTubeReq req)
	{
		Submarine s = submarine;
		if (s is null)
			return;
		synchronized(s.simulator.simMut.reader)
		{
			if (s !is submarine)
				return;
			Tube tube = s.getTube(req.tubeId);
			// reference frame translation for courses
			foreach (ref WeaponParamValue param; req.weaponParams)
			{
				if (param.type == WeaponParamType.course)
				{
					param.course = param.course - coordRot;
				}
			}
			TubeOperationResult topRes = tube.processLaunchRequest(
				req.weaponName, req.weaponParams);
			PlayerConnection con = m_connection;
			if (con && topRes.tubeChanged)
			{
				assert(topRes.launchOccurred);
				con.sendMessage(immutable TubeStateUpdateRes(
					tube.fullState, true, topRes.launchedWeaponName));
				if (topRes.wireGuidanceId)
				{
					// send wire guidance full state
					WireGuidanceFullState guidanceState =
						tube.wireGuidedWeapon.guidance.getFullState(true);
					// client space transformations
					guidanceState.weaponSnap = snapToClientSpace(
						guidanceState.weaponSnap);
					guidanceState.trackingDir = rotToClientSpace(guidanceState.trackingDir);
					foreach (ref WeaponParamValue param; guidanceState.weaponParams)
					{
						if (param.type == WeaponParamType.course)
						{
							param.course = param.course + coordRot;
						}
					}
					con.sendMessage(cast(immutable) WireGuidanceStateRes(guidanceState));
				}
			}
			assert(!topRes.roomChanged);
		}
	}

	private KinematicSnapshot genSubSnapshot(Submarine s)
	{
		assert(s);
		return snapToClientSpace(s.kinematicSnapshot);
	}

	private WireSnapshot[] genSubWireSnapshots(Submarine s)
	{
		assert(s);
		WireSnapshot[] res;
		usecs_t worldTime = s.simulator.worldTime;
		for (size_t i = 0; i < s.rigidBody.wires.length; i++)
		{
			AttachedWire wire = s.rigidBody.wires[i];
			WireSnapshot wireSnap;
			wireSnap.atTime = worldTime + timeShift;
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

	KinematicSnapshot snapToClientSpace(KinematicSnapshot snap) const
	{
		KinematicSnapshot res = KinematicSnapshot(
			snap.atTime + timeShift,
			posToClientSpace(snap.position),
			dirToClientSpace(snap.velocity),
			rotToClientSpace(snap.rotation),
			snap.angVel);
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

	// called from simulator thread while holding simulator's write lock
	void handleSimTerminating(Submarine terminatedSub)
	{
		PlayerConnection con = m_connection;
		bool shouldUnsetSub = terminatedSub is submarine;
		if (con && shouldUnsetSub)
		{
			con.simulatorFlow = false;
			if (con.isOpen)
				con.sendMessage(immutable SimulatorTerminatingRes());
		}
		if (shouldUnsetSub)
			unsetSubmarine(terminatedSub);
	}

	// simMut.writer is held by the simulator
	void sendPauseStateUpdate(Submarine subToUpdate, bool isSimPaused)
	{
		Submarine s = submarine;

		// Dangling submarine reference protection
		// TODO: verify the need in this check.
		if (subToUpdate !is s)
			return;

		PlayerConnection con = m_connection;
		if (con && con.isOpen && con.simulatorFlow && (con.simFlowSub is s))
		{
			con.sendMessage(immutable SimulatorPausedRes(isSimPaused));
		}
	}

	// simMut.writer is held by the simulator
	void sendTimeAccelerationFactorUpdate(Submarine subToUpdate, short currentFactor)
	{
		Submarine s = submarine;

		// Dangling submarine reference protection
		// TODO: verify the need in this check.
		if (subToUpdate !is s)
			return;

		PlayerConnection con = m_connection;
		if (con && con.isOpen && con.simulatorFlow && (con.simFlowSub is s))
		{
			con.sendMessage(immutable TimeAccelerationRes(currentFactor));
		}
	}

	static string generateKillRecordReport(Submarine sub)
	{
		string res = "Your kills: \n\n";
		foreach (const KillRecord record; sub.kills)
		{
			string recStr = record.relation.to!string ~ " " ~
				record.vesselType ~ " " ~
				(record.submarineCaptain ? "(" ~ record.submarineCaptain ~ ") " : "") ~
				"with " ~ record.weaponType ~ "\n";
			res ~= recStr;
		}
		return res;
	}

	// simMut.writer is held by the simulator
	void sendUpdate(Submarine subToUpdate)
	{
		Submarine s = submarine;

		// Dangling submarine reference protection
		if (subToUpdate !is s)
			return;

		PlayerConnection con = m_connection;

		assert(s !is null);

		if (con && con.isOpen && con.simulatorFlow && (con.simFlowSub is s))
		{
			// send death message. Death has priority over defeat message.
			if (s.dead)
			{
				con.simulatorFlow = false;
				con.sendMessage(immutable SimFlowEndRes(
					SimFlowEndReason.death, s.causeOfDeath,
					generateKillRecordReport(s)));
				return;
			}
			// send scenario data: goals, map overlay or simFlowEndRes.
			Scenario scenario = s.simulator.scenario;
			if (scenario)
			{
				if (scenario.sendChangesOrFinish(this, con))
				{
					con.simulatorFlow = false;
					return;
				}
			}
			// sub's kinematic snapshot
			con.sendMessage(cast(immutable) SubKinematicRes(genSubSnapshot(s),
				genSubWireSnapshots(s)));
			// send hydrophone audio
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
					haudio ~= immutable HydrophoneAudio(i.to!int,
						rotToClientSpace(h.listenDir),
						samples, samples.length.to!int);
				}
			}
			usecs_t worldTime = s.simulator.worldTime;
			con.sendMessage(immutable HydrophoneDataStreamRes(
				worldTime + timeShift, hdata));
			// audio is too large and goes through separate, "secondary" connection
			PlayerConnection secondaryCon = con.secondaryConnection;
			if (secondaryCon)
			{
				// simple over-buffering protection for slow connections
				if (secondaryCon.writeQueueSize < 2)
				{
					secondaryCon.sendMessage(immutable HydrophoneAudioStreamRes(
						worldTime + timeShift, haudio));
				}
				else
					trace("Stalling secondary connection for player ", m_username);
			}
			// active sonar
			if (s.sonar.active && s.sonar.hasSliceToSend)
			{
				immutable SonarSliceData sdata = immutable SonarSliceData(
					0, s.sonar.pingCounter, s.sonar.readySliceId,
					s.sonar.getLastSlice());
				con.sendMessage(immutable SonarStreamRes(
					worldTime + timeShift, [sdata]));
				s.sonar.markSliceSent();
			}
			// send updates about tubes and rooms
			bool[int] updatedRooms;
			foreach (Tube tube; s.tubeRange)
			{
				if (tube.lastSimUpdateResult.tubeChanged)
					con.sendMessage(cast(immutable) TubeStateUpdateRes(tube.fullState));
				if (tube.lastSimUpdateResult.roomChanged)
					updatedRooms[tube.room.id] = true;
				// wire-guidance handling
				if (tube.lastSimUpdateResult.wireWasCut)
				{
					con.sendMessage(cast(immutable) WireGuidanceLostRes(
						tube.id, tube.lastSimUpdateResult.wireGuidanceId));
				}
				else if (tube.wireGuidanceActive)
				{
					// periodic update of every wire-guided torp
					WireGuidanceFullState fullState =
						tube.wireGuidedWeapon.guidance.getFullState(false);
					fullState.trackingDir = rotToClientSpace(fullState.trackingDir);
					fullState.weaponSnap = snapToClientSpace(fullState.weaponSnap);
					con.sendMessage(cast(immutable) WireGuidanceStateRes(fullState));
				}
			}
			foreach (int roomId; updatedRooms.byKey)
				con.sendMessage(cast(immutable) AmmoRoomStateUpdateRes(
					s.getAmmoRoom(roomId).fullState));
		}
		// handle death. m_submarine is nulled as late as possible (dictated by spin model)
		if (s.dead)
			unsetSubmarine(s);
	}

	//
	// Observer section
	//

	// Player is currently observing this simulator.
	// Reset to null when connection is closed.
	private Simulator m_observedSimulator;

	final @property Simulator observedSimulator()
	{
		return atomicLoad(m_observedSimulator);
	}

	// called from the simulator when evicting the observer
	void unsetObservedSimulator()
	{
		atomicStore(m_observedSimulator, null);
	}

	void stopObservingSimulator()
	{
		Simulator oldObservedSim = m_observedSimulator;
		if (oldObservedSim)
		{
			synchronized(oldObservedSim.simMut.reader)
			{
				oldObservedSim.unregisterObserver(m_username);
				assert(m_observedSimulator is null);
			}
		}
	}


	// rhs reader lock must be held
	ObservableEntityUpdate[] observeSimulator(Simulator rhs)
	{
		assert(rhs);
		enforce(m_submarine is null, "Player has a submarine, cannot oserve a simulator");
		Simulator oldObservedSim = m_observedSimulator;
		if (oldObservedSim)
		{
			synchronized(oldObservedSim.simMut.reader)
			{
				oldObservedSim.unregisterObserver(m_username);
				assert(m_observedSimulator is null);
			}
		}
		rhs.registerObserver(this);
		ObservableEntityUpdate[] res = rhs.getObservableEntities();
		atomicStore(m_observedSimulator, rhs);
		return res;
	}

	void sendObserverUpdate(ObservableEntityUpdate[] entityUpdates,
							SimulatorLogRecord[] logRecords,
							usecs_t atTime)
	{
		PlayerConnection con = m_connection;
		assert(m_submarine is null);
		if (con && con.isOpen && con.simulatorFlow)
		{
			DevObserverSimulatorUpdateRes msg =
				DevObserverSimulatorUpdateRes(
					atTime, entityUpdates, logRecords);
			con.sendMessage(cast(immutable) msg);
		}
	}
}


/// Set of indexed (by username) Player objects, handles concurrent
/// authorization and object eviction.
final class PlayerCollection
{
	private
	{
		Player[string] m_players;
		// map, indexed by secondary connection secrets
		Player[string] m_secondarySecrets;
	}

	/// Players map, indexed by username string
	@property Player[string] players() { return m_players; }

	/// Get or create Player for connection.
	Player authorizeConnection(PlayerConnection con, string username, string password,
		string secondaryConnectionSecret)
	{
		assert(con);
		username = strip(username);
		if (username.length == 0)
			throw new AuthException("Empty login");
		scope(success) info("Player ", username, " authorized");
		// db operations are placed outside of the lock to reduce
		// LOC. Performance is irrelevant.
		if (Globals.database)
		{
			PlayerDb* pdb = Globals.database.getPlayerByLogin(username);
			// insert may throw but that's not a problem
			if (pdb is null)
				Globals.database.insertPlayer(username, password);
			else if (!pdb.passwordMatchesHash(password))
				throw new AuthException("invalid login or password");
			sendMail("dsubs_server authentication",
				"user " ~ username ~ " has authenticated");
		}
		synchronized(this)
		{
			Player* p = username in m_players;
			if (p !is null)
			{
				// player is already present, let's try to authorize new connection
				enforce!AuthException(p.areCredentialsEqual(username, password),
					"invalid login or password");
				PlayerConnection oldConnection = p.emplaceConnection(con);
				if (oldConnection && oldConnection.secondaryConnectionSecret)
					m_secondarySecrets.remove(oldConnection.secondaryConnectionSecret);
				m_secondarySecrets[secondaryConnectionSecret] = *p;
				return *p;
			}
			else
			{
				// new player
				Player np = new Player(con, username, password);
				m_players[username] = np;
				m_secondarySecrets[secondaryConnectionSecret] = np;
				return np;
			}
		}
	}

	/// Get Player for secondary connection.
	Player authorizeSecondaryConnection(PlayerConnection con,
		string secondaryConnectionSecret)
	{
		assert(con);
		if (!secondaryConnectionSecret)
			throw new AuthException("Empty secondaryConnectionSecret");
		synchronized(this)
		{
			Player* p = secondaryConnectionSecret in m_secondarySecrets;
			if (p !is null)
			{
				// player is already present, set it's secondary connection
				p.emplaceSecondaryConnection(con);
				return *p;
			}
			else
			{
				// secret not in the known secrets map, throw
				throw new AuthException("Invalid secondaryConnectionSecret");
			}
		}
	}


	/// Remove dead subless connection-less player objects from the hash-table.
	void purgeDanglingPlayers()
	{
		string[] playersToRemove;
		synchronized(this)
		{
			foreach (Player p; m_players.byValue)
			{
				if (p.connection is null && p.submarine is null &&
						p.observedSimulator is null)
					playersToRemove ~= p.name;
			}
			foreach (uname; playersToRemove)
			{
				// lock the player object and check purge condition again
				Player p = m_players[uname];
				synchronized(p)
				{
					if (p.connection is null && p.submarine is null &&
						p.observedSimulator is null)
					{
						trace("evicting ", uname, " Player from PlayerCollection");
						m_players.remove(uname);
					}
				}
			}
		}
	}
}