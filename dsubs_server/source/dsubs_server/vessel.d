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
module dsubs_server.vessel;

import std.uuid;
import std.random: uniform;

import dsubs_common.api.entities;
import dsubs_common.event;
import dsubs_common.math;
import dsubs_common.json;
import dsubs_common.containers.array: removeFirstUnstable;

import dsubs_sound.activesonar: Reflector, ReflectorPrototype;

import dsubs_server.ai.captain: ContactRelation;
import dsubs_server.player: Captain;
import dsubs_server.common;
import dsubs_server.dynamics;
import dsubs_server.observable;
import dsubs_server.propulsion;
import dsubs_server.objfile: ObjModel;
import dsubs_server.submarine: Submarine;
import dsubs_server.simulator;


abstract class Killable: IObservableEntity
{
	private
	{
		UUID m_id;
		bool m_dead;
		usecs_t m_registerTime;
		usecs_t m_deathTime;
		string m_causeOfDeath;
		Simulator m_simulator;
		Captain m_killer;
	}

	protected ObservableEntityCache m_observableCache;

	this()
	{
		m_id = randomUUID();
	}

	final
	{
		@property UUID id() const { return m_id; }
		@property bool dead() const { return m_dead; }
		@property usecs_t deathTime() const { return m_deathTime; }
		@property usecs_t registerTime() const { return m_registerTime; }
		@property string causeOfDeath() const { return m_causeOfDeath; }
		@property Captain killer() { return m_killer; }
		@property inout(Simulator) simulator() inout { return m_simulator; }
	}

	final protected void registerSimulator(Simulator sim)
	{
		m_simulator = sim;
		m_registerTime = sim.worldTime;
	}

	// called under (this) lock
	protected void onFirstKill() {}

	/// Ensure that the vessel is dead. Returns true if it was killed first time.
	bool kill(string cause, Captain killer)
	{
		// can be called from different worker threads
		synchronized(this)
		{
			if (!m_dead)
			{
				m_dead = true;
				m_killer = killer;
				m_deathTime = m_simulator.worldTime;
				m_causeOfDeath = cause;
				onFirstKill();
				m_observableCache.log(m_id.toString(), typeof(this).stringof,
					"Entity killed, cause: " ~  cause ~ ", killer: " ~
						(killer ? killer.name() : ""));
				return true;
			}
			else
				return false;
		}
	}

	void markNewObservationEpoch()
	{
		m_observableCache.clearCache();
	}

	StructuredObservableEntityUpdate getObserverUpdate()
	{
		if (m_observableCache.generated)
			return m_observableCache.entityUpdateCache;
		updateObservableCache();
		m_observableCache.generated = true;
		return m_observableCache.entityUpdateCache;
	}

	protected void updateObservableCache()
	{
		m_observableCache.id = m_id.toString();
		m_observableCache.entityType = this.classBaseName;
		m_observableCache.stateUpdateJson["dead"] = this.dead;
		if (this.dead)
		{
			m_observableCache.stateUpdateJson["causeOfDeath"] = this.causeOfDeath;
			if (this.killer)
				m_observableCache.stateUpdateJson["killer"] = this.killer.name;
		}
	}

	size_t appendObserverLogRecords(ref SimulatorLogRecord[] appendTo)
	{
		appendTo ~= m_observableCache.logRecords;
		return m_observableCache.logRecords.length;
	}
}


struct KillRecord
{
	// relation at time of kill
	ContactRelation relation;
	// what did you kill?
	string vesselType;
	// who was the dead captain of the submarine?
	string submarineCaptain;
	// with what did you kill it?
	string weaponType;
}


interface IHasTransform
{
	@property Transform2D transform();
}


interface IHasRigidBody
{
	@property RigidBody rigidBody();
	@property const(RigidBody) rigidBody() const;
}


/// Physically-simulated vessel with propulsor, rudder and reflector components
class Vessel: Killable, IHasTransform, IHasRigidBody
{
	protected
	{
		Transform2D m_transform;
		RigidBody m_rigidBody;
		BasicRudder m_rudder;
		Propulsor[] m_propulsors;
		Reflector m_reflector;
		string m_prototypeName;
		usecs_t m_reapTime;
	}

	final
	{
		@property Transform2D transform() { return m_transform; }
		@property RigidBody rigidBody() { return m_rigidBody; }
		@property const(RigidBody) rigidBody() const { return m_rigidBody; }
		/// Propulsor is assigned before bootstrap, during spawn
		void addPropulsor(Propulsor rhs)
		{
			m_propulsors ~= rhs;
			m_transform.addChild(rhs.transform);
		}
		@property inout(Propulsor)[] propulsors() inout { return m_propulsors; }
		@property inout(BasicRudder) rudder() inout { return m_rudder; }
		@property string prototypeName() const { return m_prototypeName; }
		@property usecs_t reapTime() const { return m_reapTime; }
	}

	this(string prototypeName)
	{
		m_prototypeName = prototypeName;
		m_transform = new Transform2D();
		m_rigidBody = new RigidBody(m_transform);
		m_rigidBody.owner = this;
	}

	Event!(void delegate()) onPreKinematics;
	Event!(void delegate(usecs_t dt)) onPostKinematics;

	/// register the vessel in global component systems
	void register(Simulator sim)
	{
		registerSimulator(sim);
		m_rigidBody.updateFromTransform();
		sim.vessels.registerEntity(this);
		sim.phys.registerEntity(m_rigidBody);
		sim.acous.registerReflector(m_reflector);
		foreach (prop; m_propulsors)
			prop.register(sim);
	}

	/// call this when removing this submarine from the physical world to
	/// unregister components and dispose of resources
	void shutdown()
	{
		simulator.vessels.unregisterEntity(this);
		simulator.acous.unregisterReflector(m_reflector);
		simulator.phys.unregisterEntity(m_rigidBody);
		foreach (prop; m_propulsors)
			prop.shutdown();
	}

	final @property float targetThrottle() const
	{
		if (m_propulsors)
			return m_propulsors[0].targetThrottle;
		else
			return 0.0f;
	}

	/// set propulsor's target throttle
	final @property void targetThrottle(float target)
	{
		enforce(!isNaN(target), "NaN target throttle");
		enforce(target <= 1.0f && target >= -1.0f, "Throttle not in [-1, 1] interval");
		foreach (prop; m_propulsors)
			prop.targetThrottle = target;
	}

	final @property float targetCourse() const { return m_rudder.targetCourse; }

	/// set rudder's target course
	final @property void targetCourse(float target)
	{
		enforce(!isNaN(target), "NaN target course");
		enforce(!isInfinity(target), "Infinite target course");
		m_rudder.targetCourse = clampAngle(target);
	}

	/// Ensure that the vessel is dead. Returns true if it was killed first time.
	override bool kill(string cause, Captain killer)
	{
		bool res = super.kill(cause, killer);
		if (res)
		{
			m_reapTime = m_deathTime + uniform!("[]", usecs_t, usecs_t)(240, 360) *
				1000_000L;
			targetThrottle = 0.0f;
			// optimization: do not simulate wires of dead vessels
			if (m_rigidBody)
				m_rigidBody.wires.length = 0;
		}
		return res;
	}

	final @property KinematicSnapshot kinematicSnapshot()
	{
		return KinematicSnapshot(
			simulator.worldTime,
			m_transform.wposition,
			m_rigidBody.kinet.vel,
			m_transform.wrotation,
			m_rigidBody.kinet.angVel);
	}

	override void updateObservableCache()
	{
		super.updateObservableCache();
		m_observableCache.transformSnapshot = this.kinematicSnapshot;
		m_observableCache.stateUpdateJson["prototypeName"] = this.prototypeName;
		m_observableCache.stateUpdateJson["speed"] = this.rigidBody.kinet.velLength;
		m_observableCache.stateUpdateJson["mass"] = this.rigidBody.mass;
		m_observableCache.stateUpdateJson["targetThrottle"] = this.targetThrottle;
		m_observableCache.stateUpdateJson["course"] =
			-this.rigidBody.kinet.rotation.compassAngle.rad2dgr;
		m_observableCache.stateUpdateJson["targetCourse"] =
			-this.targetCourse.compassAngle.rad2dgr;
	}
}


/// Set of vessels that are active
final class VesselCollection: IObservableCollection
{
	private
	{
		Vessel[] m_entities;
		// subset of m_entities
		Submarine[] m_submarines;
	}

	@property inout(Vessel)[] entities() inout { return m_entities; }
	@property inout(Submarine)[] submarines() inout { return m_submarines; }

	/// range of not-dead submarines
	@property auto aliveSubmarines()
	{
		return m_submarines.filter!(sub => !sub.dead);
	}

	/// range of not-dead submarines that have a human player
	@property auto alivePlayerSubmarines()
	{
		return m_submarines.filter!(sub => !sub.dead && sub.player !is null);
	}

	void registerEntity(Vessel e)
	{
		synchronized(this)
		{
			m_entities ~= e;
			Submarine sub = cast(Submarine) e;
			if (sub)
				m_submarines ~= sub;
		}
	}

	void unregisterEntity(Vessel e)
	{
		synchronized(this)
		{
			m_entities.removeFirstUnstable(e);
			Submarine sub = cast(Submarine) e;
			if (sub)
				m_submarines.removeFirstUnstable(sub);
		}
	}

	void shutdownAll()
	{
		Vessel[] vessels = m_entities.dup;
		foreach (v; vessels)
			v.shutdown();
		assert(m_entities.length == 0, "vessel leak");
		assert(m_submarines.length == 0, "submarine leak");
	}

	void preKinematics()
	{
		foreach (vessel; Globals.taskPool.parallel(m_entities, 8))
			vessel.onPreKinematics();
	}

	void postKinematics(usecs_t dt)
	{
		foreach (vessel; Globals.taskPool.parallel(m_entities, 8))
			vessel.onPostKinematics(dt);
	}

	/// Shutdown dead vessels that have reapTime in the past
	void collectDeadVessels(usecs_t currentWorldTime)
	{
		Vessel[] deadVessels;
		foreach (vessel; m_entities)
		{
			if (vessel.dead && vessel.reapTime < currentWorldTime)
				deadVessels ~= vessel;
		}
		foreach (v; deadVessels)
			v.shutdown();
	}

	/// clear the container
	void clean()
	{
		m_submarines.length = 0;
		m_entities.length = 0;
	}

	mixin ObservableCollectionCommonMethods;
}


/// MountPoint that gets it's center from .obj model
struct MountPointConfig
{
	/// name of the plane in the model, which center will be used
	/// as mount-center
	string mountCenterPlane;
	MountPoint mountPoint;

	void setCenterFromModel(ref const ObjModel model)
	{
		if (mountCenterPlane)
		{
			enforce(mountCenterPlane in model.allFaces,
				"plane " ~ mountCenterPlane ~ " not found in model");
			mountPoint.mountCenter = model.allFaces[mountCenterPlane].center;
		}
	}

	alias mountPoint this;
}


struct VesselRigidBodyConfig
{
	RolledF mass, Cd0, Cd1, Cr0, Cr1, Cl, Cm;
	double Cda;
	float moiK = 1.0f;
	float hullLength;
}

struct VesselSteeringConfig
{
	/// Equilibrium drift angle on maximum rudder deflection, radians
	float equilDrift = 0.0f;
	float rudderKp = 10.0f;
	float rudderKd = -20.0f;
	float rudderPosChangeSpeed = 1.0f;
}


/// Serializable vessel config
class VesselFactoryConfig
{
	VesselRigidBodyConfig rigidBody;
	ReflectorPrototype reflector;
	VesselSteeringConfig steering;

	JSONValue toJsonDynamic()
	{
		throw new Exception("not implemented");
	}
}


class VesselFactory
{
	VesselFactoryConfig vesselConfig;

	double calcMoi(float totalMass) const
	{
		return vesselConfig.rigidBody.moiK * totalMass * pow(vesselConfig.rigidBody.hullLength, 2) / 12.0;
	}

	/// internal binding and preparation of vessel components
	protected final void bootstrap(Vessel res) const
	{
		res.m_rigidBody.mass = vesselConfig.rigidBody.mass;
		res.m_rigidBody.hydroModel.Cd0 = vesselConfig.rigidBody.Cd0;
		res.m_rigidBody.hydroModel.Cd1 = vesselConfig.rigidBody.Cd1;
		res.m_rigidBody.hydroModel.Cda = vesselConfig.rigidBody.Cda;
		res.m_rigidBody.hydroModel.Cr0 = vesselConfig.rigidBody.Cr0;
		res.m_rigidBody.hydroModel.Cr1 = vesselConfig.rigidBody.Cr1;
		res.m_rigidBody.hydroModel.Cl = vesselConfig.rigidBody.Cl;
		res.m_rigidBody.hydroModel.Cm = -vesselConfig.rigidBody.Cm.roll();
		// res.m_rigidBody.kinet.angVel = 1.0;
		auto brudder = new BasicRudder();
		brudder.transform = res.transform;
		brudder.Kp = vesselConfig.steering.rudderKp;
		brudder.Kd = vesselConfig.steering.rudderKd;
		brudder.posChangeSpeed = vesselConfig.steering.rudderPosChangeSpeed;
		// Cm * equilDrift = steeringK
		brudder.steeringK = fabs(vesselConfig.steering.equilDrift * res.m_rigidBody.hydroModel.Cm);
		res.m_rudder = brudder;
		// reflector
		res.m_reflector = new Reflector(res.transform, vesselConfig.reflector);
		res.m_reflector.owner = res;
		// rudder and propulsor
		assert(res.m_rudder !is null);
		res.m_rigidBody.forces = [cast(IForce) res.m_rudder];
		foreach(prop; res.m_propulsors)
		{
			res.m_rigidBody.forces ~= cast(IForce) prop;
			// add module masses to the hull
			res.m_rigidBody.mass += prop.mass;
		}
		// calculate final MOI
		res.m_rigidBody.moi = calcMoi(res.m_rigidBody.mass);
		foreach(prop; res.m_propulsors)
			prop.bootstrap(res.m_rigidBody);
		assert(!isNaN(res.m_rigidBody.mass));
		assert(!isNaN(res.m_rigidBody.moi));
	}
}
