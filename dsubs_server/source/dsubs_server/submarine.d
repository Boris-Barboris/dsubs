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
module dsubs_server.submarine;

import std.typecons: Nullable;

import dsubs_common.api.entities;
import dsubs_common.math;

import dsubs_sound.activesonar;
import dsubs_sound.hydrophone;

import dsubs_server.ai.captain: ContactRelation;
import dsubs_server.common;
import dsubs_server.vessel;
import dsubs_server.sensors;
import dsubs_server.simulator;
import dsubs_server.weaponry;
import dsubs_server.torpedo: Weapon;
import dsubs_server.dynamics: AttachedWire, AttachedWirePrototype;
import dsubs_server.propulsion: Propulsor;
import dsubs_server.player: Player, Captain;


/// Server-side model of a submarine
final class Submarine: Vessel
{
	private
	{
		Hydrophone[] m_hydrophones;
		ActiveSonar m_sonar;
		Captain m_captain;
		Tube[int] m_tubes;
		AmmoRoom[int] m_rooms;
		KillRecord[] m_kills;
		// connection reference cnounter
		int m_conRefCount;
	}

	// reference counters work in lockstep with simulator's reference counter in
	// order to have up-to-date integer number of connections that depend on
	// simulator.

	@property int conRefCount() const { return m_conRefCount; }

	void incSubConRefCounter()
	{
		synchronized(this)
		{
			if (m_conRefCount == 0 && simulator)
			{
				simulator.incConnectedPlayers();
			}
			m_conRefCount++;
		}
	}

	void decSubConRefCounter()
	{
		synchronized(this)
		{
			if (m_conRefCount == 1 && !dead && simulator)
			{
				simulator.decConnectedPlayers();
			}
			m_conRefCount--;
			assert(m_conRefCount >= 0);
		}
	}

	override protected void onFirstKill()
	{
		if (m_conRefCount > 0 && simulator)
			simulator.decConnectedPlayers();
	}

	@property Hydrophone[] hydrophones() { return m_hydrophones; }
	@property ActiveSonar sonar() { return m_sonar; }

	@property const(KillRecord)[] kills() const { return m_kills; }

	void addKillRecord(KillRecord rec)
	{
		m_kills ~= rec;
	}

	@property Captain captain() { return m_captain; }
	@property void captain(Captain rhs) { m_captain = rhs; }

	ContactRelation relationWith(Vessel v)
	{
		if (captain is null || captain.side is null)
			return ContactRelation.unknown;
		Submarine sub = cast(Submarine) v;
		if (sub)
		{
			if (sub.captain is null)
				return ContactRelation.unknown;
			return captain.side.relateTo(sub.captain.side);
		}
		Weapon wpn = cast(Weapon) v;
		if (wpn)
		{
			if (wpn.shooterCaptain is null)
				return ContactRelation.unknown;
			return captain.side.relateTo(wpn.shooterCaptain.side);
		}
		return ContactRelation.unknown;
	}

	/// result of captain's cast to Player class. Effectively a human player, if not null.
	@property inout(Player) player() inout { return cast(inout(Player)) m_captain; }

	override string toString()
	{
		return "Submarine (proto: " ~ prototypeName ~
			(m_captain ? ", captain: " ~ m_captain.toString() : "") ~
			(player ? ", player: " ~ player.name : "") ~
			")";
	}

	/// creates transform and rigid body. Sets Captain and Submarine cross-references.
	this(Captain captain, string prototypeName)
	{
		super(prototypeName);
		m_captain = captain;
		if (m_captain)
			m_captain.submarine = this;
	}

	Tube getTube(int id)
	{
		enforce(id in m_tubes);
		return m_tubes[id];
	}

	auto tubeRange() { return m_tubes.byValue; }
	auto tubeRange() const { return m_tubes.byValue; }

	size_t tubeCount() const { return m_tubes.length; }

	Weapon getWireGuidedWeapon(string wireGuidanceId)
	{
		foreach (tube; tubeRange)
		{
			if (tube.wireGuidanceId == wireGuidanceId)
				return tube.wireGuidedWeapon;
		}
		return null;
	}

	inout(AmmoRoom) getAmmoRoom(int id) inout
	{
		enforce(id in m_rooms);
		return m_rooms[id];
	}

	auto ammoRoomRange() const { return m_rooms.byValue; }
	// dmd bug forces to duplicate
	auto ammoRoomRange() { return m_rooms.byValue; }

	override void register(Simulator sim)
	{
		super.register(sim);
		foreach (h; m_hydrophones)
			sim.acous.registerHydrophone(h);
		if (m_sonar)
			sim.acous.registerSonar(m_sonar);
	}

	override void shutdown()
	{
		super.shutdown();
		foreach (h; m_hydrophones)
		{
			simulator.acous.unregisterHydrophone(h);
			h.release();
		}
		if (m_sonar)
		{
			simulator.acous.unregisterSonar(m_sonar);
			m_sonar.release();
		}
		if (m_captain)
		{
			m_captain.unsetSubmarine(this);
			m_captain = null;
		}
	}

	override bool kill(string cause, Captain killer)
	{
		bool res = super.kill(cause, killer);
		if (res)
		{
			foreach (h; m_hydrophones)
				h.canBeActive = false;
			if (m_sonar)
				m_sonar.active = false;
		}
		return res;
	}
}


private enum float FLOW_NOISE_INTERFERENCE_RANGE = 10.0f;


struct Submarine2DModel
{
	ConvexPolygon[] hullModel;
	int elevatedHullShapeIdx;
}

struct Submarine2DModelConfig
{
	// null if no model is used
	string modelFileName;
}

// serializable submarine factory
struct SubmarineFactoryConfig
{
	VesselFactoryConfig vesselConfig;
	string name;
	string description;
	Submarine2DModelConfig model;
	MountPointConfig[] propulsionMounts;
	string[] allowedPropulsors;
	bool playable = false;
	SubHydrophonePrototype[] hydrophones;
	SubSonarPrototype[] activeSonars;
	AmmoRoomPrototype[] ammoRooms;
	TubeConfig[] tubes;
}


final class SubmarineFactory: VesselFactory
{
	string name;
	string description;
	Submarine2DModel model;
	MountPoint[] propulsionMounts;
	string[] allowedPropulsors;
	bool playable = false;
	SubHydrophonePrototype[] hprots;
	Nullable!SubSonarPrototype asprot;
	AmmoRoomPrototype[int] roomProtos;
	TubeConfig[int] tubeProtos;

	@property const(SubmarineTemplate) tmpl() const
	{
		return const SubmarineTemplate(
			name, description, model.hullModel, propulsionMounts,
			model.elevatedHullShapeIdx, hprots.map!(hp => hp.tmpl).array,
			(!asprot.isNull) ? asprot.get.tmpl : SonarTemplate.init,
			allowedPropulsors, roomProtos.byValue.map!(rp => rp.tmpl).array,
			tubeProtos.byValue.map!(tp => tp.tmpl).array);
	}

	private void bootstrap(Submarine res) const
	{
		super.bootstrap(res);
		// propulsor shift according to first mount
		foreach (i, prop; res.propulsors)
		{
			prop.transform.position = propulsionMounts[i].mountCenter.tod;
			prop.transform.rotation = propulsionMounts[i].rotation;
		}
		// hydrophones
		foreach (i, ref hp; hprots)
		{
			Transform2D t = new Transform2D();
			t.position = hp.mount.mountCenter.tod;
			t.rotation = hp.mount.rotation;
			res.transform.addChild(t);
			Hydrophone h;
			if (hp.type == HydrophoneType.fixed)
			{
				h = new Hydrophone(Globals.sctx.queue(0), t, hp.hydroProto);
				h.onPreKinematics += ((h) => {
					h.ktsStart = res.rigidBody.kinet.progradeSpeed.mps2kts; }) (h);
				h.onPostKinematics += ((h) => {
					h.ktsEnd = res.rigidBody.kinet.progradeSpeed.mps2kts; }) (h);
			}
			else
			{
				assert(hp.type == HydrophoneType.towed);
				AttachedWire wire = new AttachedWire(t, res.rigidBody,
					hp.wirePrototype.get);
				// wire.desiredLength = 500.0f;
				res.rigidBody.wires ~= wire;
				h = new Hydrophone(Globals.sctx.queue(0), wire.sensorTransform,
					hp.hydroProto);
				h.onPreKinematics += ((h, wire) => {
					h.canBeActive = wire.sensorTransformValid;
					h.ktsStart = wire.sensorPointVel.length.mps2kts;
				}) (h, wire);
				h.onPostKinematics += ((h, wire) => {
					h.ktsEnd = wire.sensorPointVel.length.mps2kts; }) (h, wire);
			}
			res.m_hydrophones ~= h;
		}
		// active sonar
		if (!asprot.isNull)
		{
			Transform2D t = new Transform2D();
			t.position = asprot.get.mount.mountCenter.tod;
			t.rotation = asprot.get.mount.rotation;
			res.transform.addChild(t);
			res.m_sonar = new ActiveSonar(Globals.sctx.queue(0), t, 
				asprot.get.sonarProto);
			res.m_sonar.owner = res;
			res.m_sonar.onPreKinematics += ()
			{
				res.m_sonar.angVelStart = res.rigidBody.kinet.angVel;
				res.m_sonar.ktsStart = res.rigidBody.kinet.progradeSpeed.mps2kts;
			};
			res.m_sonar.onPostKinematics += ()
			{
				res.m_sonar.angVelEnd = res.rigidBody.kinet.angVel;
				res.m_sonar.ktsEnd = res.rigidBody.kinet.progradeSpeed.mps2kts;
			};
		}
		// tubes
		foreach (Tube tube; res.m_tubes.byValue)
		{
			res.onPreKinematics += &tube.onPreKinematics;
			res.onPostKinematics += &tube.onPostKinematics;
			foreach (h; res.m_hydrophones)
			{
				if ((h.transform.wposition - tube.transform.wposition).length <=
						FLOW_NOISE_INTERFERENCE_RANGE)
					h.flowNoiseMultipliers ~= tube;
			}
			if (res.m_sonar &&
				(res.m_sonar.transform.wposition - tube.transform.wposition).length <=
					FLOW_NOISE_INTERFERENCE_RANGE)
				res.m_sonar.flowNoiseMultipliers ~= tube;
		}
	}

	// untrusted roomStates and tubeStates input
	Submarine build(Captain cpt, Propulsor[] propulsors,
		const(AmmoRoomFullState)[] roomStates, const(TubeSpawnState)[] tubeStates) const
	{
		Submarine res = new Submarine(null, name);
		foreach (prop; propulsors)
			res.addPropulsor(prop);
		AmmoRoomFullState[int] specifiedRoomStates;
		foreach (rs; roomStates)
			specifiedRoomStates[rs.roomId] = cast() rs;
		foreach (roomProtoTuple; roomProtos.byKeyValue)
		{
			int roomId = roomProtoTuple.key;
			const AmmoRoomPrototype roomProto = roomProtoTuple.value;
			assert(roomId == roomProto.id);
			const(AmmoRoomFullState)* specifiedState = roomId in specifiedRoomStates;
			res.m_rooms[roomId] = new AmmoRoom(res, roomProto,
				specifiedState ? specifiedState.storedWeapons : []);
		}
		TubeSpawnState[int] specifiedTubeStates;
		foreach (ts; tubeStates)
			specifiedTubeStates[ts.tubeId] = cast() ts;
		foreach (tubeProtoTuple; tubeProtos.byKeyValue)
		{
			int tubeId = tubeProtoTuple.key;
			const TubeConfig tubeProto = tubeProtoTuple.value;
			assert(tubeId == tubeProto.tmpl.id);
			const(TubeSpawnState)* specifiedState = tubeId in specifiedTubeStates;
			res.m_tubes[tubeId] = new Tube(res, res.m_rooms[tubeProto.tmpl.roomId],
				tubeProto, specifiedState ? specifiedState.loadedWeapon : null);
		}
		bootstrap(res);
		// delayed captain assignment in order to have initialized sensors and weapons
		res.captain = cpt;
		if (cpt)
			cpt.submarine = res;
		return res;
	}
}