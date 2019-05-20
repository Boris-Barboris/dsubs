module dsubs_server.propulsion;

import dsubs_common.api.entities;
import dsubs_common.math;

import dsubs_sound.soundsource;

import dsubs_server.common;
import dsubs_server.dynamics;
import dsubs_server.vessel: Vessel;


/// module that is responsible for forward\backwards thrust
abstract class Propulsor: IForce
{
	private
	{
		Transform2D m_transform;
		string m_prototypeName;
		/// mass that is added to the hull
		float m_mass = 0.0f;
	}

	private this()
	{
		m_transform = new Transform2D();
	}

	protected
	{
		/// current thrust [-1.0, 1.0]
		float m_throttle = 0.0f;
	}

	final @property Transform2D transform() { return m_transform; }
	final @property string prototypeName() const { return m_prototypeName; }
	final @property float mass() const { return m_mass; }
	final @property float throttle() const { return m_throttle; }

	float targetThrottle = 0.0f;

	void bootstrap(RigidBody vesselRb);
	/// call to register stuff in component managers (sound)
	void register();
	/// call to unregister from component managers and dispose of resources
	void shutdown();
}

/// simple propulsor with linear thrust law
final class BasicPropulsor: Propulsor
{
	private
	{
		/// how fast rotSpd can change
		float rotAcceleration = 0.25f;
		float posThrustK;
		float negThrustK;
		float shaftRotFreq = 1.0f;

		PropellerSound m_sound;
		RigidBody m_vesselRb;
	}

	private this() {}

	vec2d getForce(const RigidBody b, ref const Kinematics c)
	{
		double absThrust = m_throttle * m_throttle * (m_throttle >= 0.0f ? posThrustK : -negThrustK);
		assert(!isNaN(absThrust));
		return transform.wforward * absThrust;
	}

	double getTorque(const RigidBody b, ref const Kinematics c)
	{
		return 0.0;
	}

	void propagateInTime(float dt)
	{
		m_throttle = cmove(m_throttle, targetThrottle, rotAcceleration, dt);
	}

	override void bootstrap(RigidBody vesselRb)
	{
		m_vesselRb = vesselRb;
		m_sound.onPreSimulation += ()
		{
			m_sound.preUpdate(m_throttle * shaftRotFreq, m_vesselRb.kinet.progradeSpeed);
		};
		m_sound.onPostSimulation += (float dt)
		{
			m_sound.postUpdate(m_throttle * shaftRotFreq, m_vesselRb.kinet.progradeSpeed, dt);
		};
	}

	override void register()
	{
		Globals.acous.registerSource(m_sound);
	}

	override void shutdown()
	{
		Globals.acous.unregisterSource(m_sound);
	}
}


final class PropulsorFactory
{
	immutable PropulsorTemplate tmpl;
	RolledF posThrustK;
	RolledF negThrustK;
	float mass;
	float shaftRotFreq = 1.0f;
	float rotAcceleration = 0.25f;
	PropellerSoundPrototype soundPrototype;

	this(immutable PropulsorTemplate t)
	{
		tmpl = t;
	}

	BasicPropulsor build() const
	{
		BasicPropulsor res = new BasicPropulsor();
		res.posThrustK = posThrustK;
		res.negThrustK = negThrustK;
		res.rotAcceleration = rotAcceleration;
		res.m_prototypeName = tmpl.name;
		res.m_mass = mass;
		res.shaftRotFreq = shaftRotFreq;
		res.m_sound = new PropellerSound(res.transform, soundPrototype);
		return res;
	}
}


abstract class Rudder: IForce
{
	Transform2D transform;
	protected float m_rudderPos = 0.0f;

	/// target course, world-space
	float targetCourse = 0.0f;
}

/// PD-controlled rudder with direct mode
final class BasicRudder: Rudder
{
	/// actual torque power
	float steeringK = 0.0f;
	// PD controller gains
	float Kp = 10.0f;
	float Kd = -20.0;
	float posChangeSpeed = 1.0f;
	bool directMode;

	/// assign the target rudder position, used in directMode
	@property void directRudderPos(float rhs)
	{
		assert(rhs >= -1.0f && rhs <= 1.0f);
		m_directTarget = rhs;
	}

	private
	{
		float error = 0.0;
		float errorDeriv = 0.0;
		float m_directTarget = 0.0f;
	}

	vec2d getForce(const RigidBody b, ref const Kinematics c)
	{
		// TODO: there should be small lift here but fuck it
		return vec2d(0.0, 0.0);
	}

	double getTorque(const RigidBody b, ref const Kinematics c)
	{
		error = angleDist(targetCourse, transform.wrotation);
		errorDeriv = c.angVel;
		double absSin = fabs(sin(c.AoA));
		double aoaScale = 1.0 - fmin(0.95, 2.0 * absSin);
		return steeringK * m_rudderPos * c.velSquaredLength * aoaScale;
	}

	void propagateInTime(float dt)
	{
		float targetm_rudderPos = directMode ? m_directTarget : sgn(error);
		if (!directMode)
		{
			if (fabs(error) < dgr2rad(30))
				targetm_rudderPos = clamp(Kp * error + Kd * errorDeriv, -1.0f, 1.0f);
		}
		m_rudderPos = cmove(m_rudderPos, targetm_rudderPos, posChangeSpeed, dt);
	}
}


/// Given a hydrodynamics force model and basic propulsor, calculate flank speed
double maxSpeed(const HydroForceModel hfm, const BasicPropulsor bp)
{
	double maxT = bp.posThrustK;
	// maxT = Cd0 * v + Cd1 * v * v
	// Cd1 * v * v + Cd0 * v - maxT = 0
	double D = pow(hfm.Cd0, 2) + 4 * hfm.Cd1 * maxT;
	double vmax = (-hfm.Cd0 + sqrt(D)) / (2 * hfm.Cd1);
	assert(!isNaN(vmax));
	return vmax;
}

/// Given constructed vessel, return the
float throttleForSpeed(Vessel v, float speed)
{
	double maxSpd = maxSpeed(v.rigidBody.hydroModel, cast(BasicPropulsor) v.propulsor);
	if (maxSpd == 0.0f)
		return 0.0f;
	return clamp(speed / maxSpd, -1.0f, 1.0f);
}