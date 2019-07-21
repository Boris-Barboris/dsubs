module dsubs_server.vessel;

import dsubs_common.api.entities;
import dsubs_common.event;
import dsubs_common.math;
import dsubs_common.containers.array: removeFirstUnstable;

import dsubs_sound.activesonar: Reflector, ReflectorPrototype;

import dsubs_server.common;
import dsubs_server.dynamics;
import dsubs_server.propulsion;


/// Physically-simulated vessel with propulsor, rudder and reflector components
class Vessel
{
	protected
	{
		Transform2D m_transform;
		RigidBody m_rigidBody;
		float m_moiK = 1.0f;
		float m_hullLength;
		BasicRudder m_rudder;
		Propulsor m_propulsor;
		Reflector m_reflector;
		string m_prototypeName;
		bool m_dead;
		usecs_t m_deathTime;
		string m_causeOfDeath;
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
		@property bool dead() const { return m_dead; }
		@property usecs_t deathTime() const { return m_deathTime; }
		@property string causeOfDeath() const { return m_causeOfDeath; }
	}

	this(string prototypeName)
	{
		m_prototypeName = prototypeName;
		m_transform = new Transform2D();
		m_rigidBody = new RigidBody(m_transform);
		m_rigidBody.vesselOwner = this;
	}

	Event!(void delegate()) onPreKinematics;
	Event!(void delegate(usecs_t dt)) onPostKinematics;

	private double calcMoi() const
	{
		return m_moiK * m_rigidBody.mass * m_hullLength * m_hullLength / 12.0;
	}

	/// register the vessel in global component systems
	void register()
	{
		m_rigidBody.updateFromTransform();
		Globals.vessels.registerEntity(this);
		Globals.phys.registerEntity(m_rigidBody);
		Globals.acous.registerReflector(m_reflector);
		if (m_propulsor)
			m_propulsor.register();
	}

	/// call this when removing this submarine from the physical world to
	/// unregister components and dispose of resources
	void shutdown()
	{
		Globals.vessels.unregisterEntity(this);
		Globals.acous.unregisterReflector(m_reflector);
		Globals.phys.unregisterEntity(m_rigidBody);
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
	bool kill(string cause)
	{
		if (!m_dead)
		{
			m_deathTime = Globals.sim.worldTime;
			if (m_propulsor)
				targetThrottle = 0.0f;
			m_dead = true;
			m_causeOfDeath = cause;
			return true;
		}
		return false;
	}
}


/// Set of vessels that are active
final class VesselCollection
{
	private
	{
		Vessel[] m_entities;
	}

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

	void collectDeadVessels()
	{
		Vessel[] deadVessels;
		usecs_t reapAge = uniform(240, 360) * 1000_000;
		foreach (vessel; m_entities)
		{
			if (vessel.dead && vessel.deathTime < Globals.sim.worldTime - reapAge)
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


class VesselFactory
{
	const string templateName;
	// physical characteristics
	RolledF mass, Cd0, Cd1, Cr0, Cr1, Cl, Cm;
	double Cda;
	// MOI-related stuff
	float moiK = 1.0f;
	float hullLength;
	/// Equilibrium drift angle on maximum rudder deflection, radians
	float equilDrift;
	ReflectorPrototype reflprot;
	float rudderKp = 10.0f;
	float rudderKd = -20.0f;
	float rudderPosChangeSpeed = 1.0f;

	this(string templateName)
	{
		this.templateName = templateName;
	}

	/// All internal binding and preparation of vessel components
	protected final void bootstrap(Vessel res) const
	{
		res.m_moiK = moiK;
		res.m_hullLength = hullLength;
		res.m_rigidBody.mass = mass;
		res.m_rigidBody.hydroModel.Cd0 = Cd0;
		res.m_rigidBody.hydroModel.Cd1 = Cd1;
		res.m_rigidBody.hydroModel.Cda = Cda;
		res.m_rigidBody.hydroModel.Cr0 = Cr0;
		res.m_rigidBody.hydroModel.Cr1 = Cr1;
		res.m_rigidBody.hydroModel.Cl = Cl;
		res.m_rigidBody.hydroModel.Cm = -Cm.roll();
		// res.m_rigidBody.kinet.angVel = 1.0;
		auto brudder = new BasicRudder();
		brudder.transform = res.transform;
		brudder.Kp = rudderKp;
		brudder.Kd = rudderKd;
		brudder.posChangeSpeed = rudderPosChangeSpeed;
		// Cm * equilDrift = steeringK
		brudder.steeringK = fabs(equilDrift * res.m_rigidBody.hydroModel.Cm);
		res.m_rudder = brudder;
		// reflector
		res.m_reflector = new Reflector(res.transform, reflprot);
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
		res.m_rigidBody.moi = res.calcMoi();
		if (res.m_propulsor)
			res.m_propulsor.bootstrap(res.m_rigidBody);
		assert(!isNaN(res.m_rigidBody.mass));
		assert(!isNaN(res.m_rigidBody.moi));
	}
}