module dsubs_server.vessel;

import std.random: uniform;

import dsubs_common.api.entities;
import dsubs_common.event;
import dsubs_common.math;
import dsubs_common.containers.array: removeFirstUnstable;

import dsubs_sound.activesonar: Reflector, ReflectorPrototype;

import dsubs_server.common;
import dsubs_server.dynamics;
import dsubs_server.propulsion;
import dsubs_server.simulator;


abstract class Killable
{
	private
	{
		bool m_dead;
		usecs_t m_deathTime;
		string m_causeOfDeath;
		Simulator m_simulator;
	}

	final
	{
		@property bool dead() const { return m_dead; }
		@property usecs_t deathTime() const { return m_deathTime; }
		@property string causeOfDeath() const { return m_causeOfDeath; }
		@property inout(Simulator) simulator() inout { return m_simulator; }
	}

	final protected void registerSimulator(Simulator sim)
	{
		m_simulator = sim;
	}

	/// Ensure that the vessel is dead. Returns true if it was killed first time.
	bool kill(string cause)
	{
		synchronized(this)
		{
			if (!m_dead)
				m_dead = true;
			else
				return false;
		}
		m_deathTime = m_simulator.worldTime;
		m_causeOfDeath = cause;
		return true;
	}
}


/// Physically-simulated vessel with propulsor, rudder and reflector components
class Vessel: Killable
{
	protected
	{
		Transform2D m_transform;
		RigidBody m_rigidBody;
		BasicRudder m_rudder;
		Propulsor m_propulsor;
		Reflector m_reflector;
		string m_prototypeName;
		usecs_t m_reapTime;
	}

	final
	{
		@property Transform2D transform() { return m_transform; }
		@property RigidBody rigidBody() { return m_rigidBody; }
		/// Propulsor is assigned before bootstrap, during spawn
		@property void propulsor(Propulsor rhs)
		{
			assert(m_propulsor is null, "only can assign propulsor once");
			m_propulsor = rhs;
			m_transform.addChild(rhs.transform);
		}
		@property inout(Propulsor) propulsor() inout { return m_propulsor; }
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
		if (m_propulsor)
			m_propulsor.register(sim);
	}

	/// call this when removing this submarine from the physical world to
	/// unregister components and dispose of resources
	void shutdown()
	{
		sim.vessels.unregisterEntity(this);
		sim.acous.unregisterReflector(m_reflector);
		sim.phys.unregisterEntity(m_rigidBody);
		if (m_propulsor)
			m_propulsor.shutdown();
	}

	final @property float targetThrottle() const { return m_propulsor.targetThrottle; }

	/// set propulsor's target throttle
	final @property void targetThrottle(float target)
	{
		enforce(!isNaN(target), "NaN target throttle");
		enforce(m_propulsor, "vessel has no propulsor");
		enforce(target <= 1.0f && target >= -1.0f, "Throttle not in [-1, 1] interval");
		m_propulsor.targetThrottle = target;
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
	override bool kill(string cause)
	{
		bool res = super.kill(cause);
		if (res)
		{
			m_reapTime = m_deathTime + uniform!("[]", usecs_t, usecs_t)(240, 360) *
				1000_000L;
			if (m_propulsor)
				targetThrottle = 0.0f;
			// optimization: do not simulate wires of dead vessels
			if (m_rigidBody)
				m_rigidBody.wires.length = 0;
		}
		return res;
	}
}


/// Set of vessels that are active
final class VesselCollection
{
	private
	{
		Vessel[] m_entities;
	}

	@property inout(Vessel)[] entities() inout { return m_entities; }

	void registerEntity(Vessel e)
	{
		synchronized(this)
		{
			m_entities ~= e;
		}
	}

	void unregisterEntity(Vessel e)
	{
		synchronized(this)
		{
			m_entities.removeFirstUnstable(e);
		}
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

	/// shutdown all elements of the collection and clear the container
	void clean()
	{
		Vessel[] entities = m_entities;
		foreach(e; entities)
			e.shutdown();
		assert(m_entities.length == 0, "vessel leak");
	}
}


struct VesselRigidBodyTemplate
{
	RolledF mass, Cd0, Cd1, Cr0, Cr1, Cl, Cm;
	double Cda;
	float moiK = 1.0f;
	float hullLength;
}

struct VesselSteeringTemplate
{
	/// Equilibrium drift angle on maximum rudder deflection, radians
	float equilDrift = 0.0f;
	float rudderKp = 10.0f;
	float rudderKd = -20.0f;
	float rudderPosChangeSpeed = 1.0f;
}


class VesselFactory
{
	VesselRigidBodyTemplate rigidBody;
	ReflectorPrototype reflprot;
	VesselSteeringTemplate steering;

	double calcMoi(float totalMass) const
	{
		return rigidBody.moiK * totalMass * pow(rigidBody.hullLength, 2) / 12.0;
	}

	/// All internal binding and preparation of vessel components
	protected final void bootstrap(Vessel res) const
	{
		res.m_rigidBody.mass = rigidBody.mass;
		res.m_rigidBody.hydroModel.Cd0 = rigidBody.Cd0;
		res.m_rigidBody.hydroModel.Cd1 = rigidBody.Cd1;
		res.m_rigidBody.hydroModel.Cda = rigidBody.Cda;
		res.m_rigidBody.hydroModel.Cr0 = rigidBody.Cr0;
		res.m_rigidBody.hydroModel.Cr1 = rigidBody.Cr1;
		res.m_rigidBody.hydroModel.Cl = rigidBody.Cl;
		res.m_rigidBody.hydroModel.Cm = -rigidBody.Cm.roll();
		// res.m_rigidBody.kinet.angVel = 1.0;
		auto brudder = new BasicRudder();
		brudder.transform = res.transform;
		brudder.Kp = steering.rudderKp;
		brudder.Kd = steering.rudderKd;
		brudder.posChangeSpeed = steering.rudderPosChangeSpeed;
		// Cm * equilDrift = steeringK
		brudder.steeringK = fabs(steering.equilDrift * res.m_rigidBody.hydroModel.Cm);
		res.m_rudder = brudder;
		// reflector
		res.m_reflector = new Reflector(res.transform, reflprot);
		res.m_reflector.owner = res;
		// rudder and propulsor
		assert(res.m_rudder !is null);
		if (res.m_propulsor)
		{
			res.m_rigidBody.forces = [
				cast(IForce) res.m_rudder, cast(IForce) res.m_propulsor];
			// add module masses to the hull
			res.m_rigidBody.mass += res.m_propulsor.mass;
		}
		else
			res.m_rigidBody.forces = [cast(IForce) res.m_rudder];
		// calculate final MOI
		res.m_rigidBody.moi = calcMoi(res.m_rigidBody.mass);
		if (res.m_propulsor)
			res.m_propulsor.bootstrap(res.m_rigidBody);
		assert(!isNaN(res.m_rigidBody.mass));
		assert(!isNaN(res.m_rigidBody.moi));
	}
}