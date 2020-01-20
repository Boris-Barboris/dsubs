module dsubs_server.submarine;

import dsubs_common.api.entities;
import dsubs_common.math;

import dsubs_sound.activesonar;
import dsubs_sound.hydrophone;

import dsubs_server.common;
import dsubs_server.vessel;
import dsubs_server.weaponry;
import dsubs_server.dynamics: AttachedWire;
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
		int m_spawnId;
		Tube[int] m_tubes;
		AmmoRoom[int] m_rooms;
	}

	@property int spawnId() const { return m_spawnId; }
	@property inout(Hydrophone)[] hydrophones() inout { return m_hydrophones; }
	@property ActiveSonar sonar() { return m_sonar; }

	@property Captain captain() { return m_captain; }
	@property void captain(Captain rhs) { m_captain = rhs; }

	/// result of captain's cast to Player class. Effectively a human player.
	@property Player player() { return cast(Player) m_captain; }

	override string toString()
	{
		return "Submarine (proto: " ~ prototypeName ~
			(m_captain ? ", captain: " ~ m_captain.toString() : "") ~
			(player ? ", player: " ~ player.name : "") ~
			")";
	}

	/// creates transform and rigid body
	this(Captain captain, string prototypeName)
	{
		super(prototypeName);
		m_captain = captain;
		if (m_captain)
			m_captain.submarine = this;
		m_spawnId = uniform(0, int.max);
	}

	Tube getTube(int id)
	{
		enforce(id in m_tubes);
		return m_tubes[id];
	}

	auto tubeRange() { return m_tubes.byValue; }
	auto tubeRange() const { return m_tubes.byValue; }

	size_t tubeCount() const { return m_tubes.length; }

	inout(AmmoRoom) getAmmoRoom(int id) inout
	{
		enforce(id in m_rooms);
		return m_rooms[id];
	}

	auto ammoRoomRange() const { return m_rooms.byValue; }
	// dmd bug forces to duplicate
	auto ammoRoomRange() { return m_rooms.byValue; }

	override void register()
	{
		super.register();
		foreach (h; m_hydrophones)
			Globals.acous.registerHydrophone(h);
		if (m_sonar)
			Globals.acous.registerSonar(m_sonar);
	}

	override void shutdown()
	{
		super.shutdown();
		foreach (h; m_hydrophones)
		{
			Globals.acous.unregisterHydrophone(h);
			h.release();
		}
		if (m_sonar)
		{
			Globals.acous.unregisterSonar(m_sonar);
			m_sonar.release();
		}
		if (m_captain)
		{
			m_captain.unsetSubmarine(this);
			m_captain = null;
		}
	}

	override bool kill(string cause)
	{
		bool res = super.kill(cause);
		if (res)
		{
			foreach (h; m_hydrophones)
				h.active = false;
			if (m_sonar)
				m_sonar.active = false;
		}
		return res;
	}
}


final class SubmarineFactory: VesselFactory
{
	immutable SubmarineTemplate tmpl;
	bool playable = false;
	HydrophonePrototype[] hprots;
	ActiveSonarPrototype* asprot;
	AmmoRoomPrototype[int] roomProtos;
	TubePrototype[int] tubeProtos;

	this(immutable SubmarineTemplate t)
	{
		super(t.name);
		tmpl = t;
	}

	private void bootstrap(Submarine res) const
	{
		super.bootstrap(res);
		// propulsor shift according to first mount
		assert(tmpl.propulsionMounts.length == 1);
		res.propulsor.transform.position = tmpl.propulsionMounts[0].mountCenter.tod;
		res.propulsor.transform.rotation = tmpl.propulsionMounts[0].rotation;
		// hydrophones
		foreach (i, ref hp; hprots)
		{
			Transform2D t = new Transform2D();
			t.position = tmpl.hydrophones[i].mount.mountCenter.tod;
			t.rotation = tmpl.hydrophones[i].mount.rotation;
			res.transform.addChild(t);
			Hydrophone h = new Hydrophone(Globals.sctx.queue(0), t, hp);
			res.m_hydrophones ~= h;
			h.onPreKinematics += { h.ktsStart = res.rigidBody.kinet.progradeSpeed.mps2kts; };
			h.onPostKinematics += { h.ktsEnd = res.rigidBody.kinet.progradeSpeed.mps2kts; };
		}
		// active sonar
		{
			Transform2D t = new Transform2D();
			t.position = tmpl.sonar.mount.mountCenter.tod;
			t.rotation = tmpl.sonar.mount.rotation;
			res.transform.addChild(t);
			if (asprot)
			{
				res.m_sonar = new ActiveSonar(Globals.sctx.queue(0), t, *asprot);
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
		}
		// tubes
		foreach (Tube tube; res.m_tubes.byValue)
		{
			res.onPreKinematics += &tube.onPreKinematics;
			res.onPostKinematics += &tube.onPostKinematics;
			foreach (h; res.m_hydrophones)
				h.flowNoiseMultipliers ~= tube;
			if (res.m_sonar)
				res.m_sonar.flowNoiseMultipliers ~= tube;
		}
		// wires
		foreach (const MountPoint wireMount; tmpl.wireMounts)
		{
			AttachedWire* wire = new AttachedWire();
			wire.attachTransform = new Transform2D();
			wire.attachTransform.position = wireMount.mountCenter.to!vec2d;
			res.transform.addChild(wire.attachTransform);
			wire.rigidBody = res.rigidBody;
			wire.maxLength = 500.0f;
			wire.desiredLength = 500.0f;
			res.rigidBody.wires ~= wire;
		}
	}

	// untrusted roomStates and tubeStates input
	Submarine build(Captain cpt, Propulsor prop,
		const(AmmoRoomFullState)[] roomStates, const(TubeSpawnState)[] tubeStates) const
	{
		Submarine res = new Submarine(null, tmpl.name);
		res.propulsor = prop;
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
			const TubePrototype tubeProto = tubeProtoTuple.value;
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