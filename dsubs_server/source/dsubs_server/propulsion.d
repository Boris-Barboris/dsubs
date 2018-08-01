module dsubs_server.propulsion;

import dsubs_common.api.entities;
import dsubs_common.math;

import dsubs_sound.soundsource;

import dsubs_server.common;
import dsubs_server.dynamics;


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

	float targetThrottle = 0.0f;

	/// call to register stuff in component managers (sound etc...)
	void bootstrap(RigidBody vesselRb);
}

/// simple propulsor with linear thrust law
final class BasicPropulsor: Propulsor
{
	private
	{
		/// how fast rotSpd can change
		float rotAcceleration = 0.34f;
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
			m_sound.preUpdate(fabs(m_throttle * shaftRotFreq), m_vesselRb.kinet.progradeSpeed);
		};
		m_sound.onPostSimulation += (float dt)
		{
			m_sound.postUpdate(fabs(m_throttle * shaftRotFreq), m_vesselRb.kinet.progradeSpeed, dt);
		};
		Globals.acous.registerSource(m_sound);
	}
}


final class PropulsorFactory
{
	immutable PropulsorTemplate tmpl;
	RolledF posThrustK;
	RolledF negThrustK;
	float mass;
	float shaftRotFreq = 1.0f;
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
		res.m_prototypeName = tmpl.name;
		res.m_mass = mass;
		res.shaftRotFreq = shaftRotFreq;
		res.m_sound = new PropellerSound(res.transform, soundPrototype);
		return res;
	}

	immutable(PropulsorTemplate)* getTemplate() const
	{
		return &tmpl;
	}
}


abstract class Rudder: IForce
{
	Transform2D transform;
	protected float rudderPos = 0.0f;

	/// target course, world-space
	float targetCourse = 0.0f;
}

/// PD-controlled rudder
final class BasicRudder: Rudder
{
	/// actual torque power
	float steeringK = 0.0f;

	private
	{
		float posChangeSpeed = 1.0f;
		// PD controller gains
		float Kp = 5.0f;
		float Kd = -45.0;

		float error = 0.0;
		float errorDeriv = 0.0;
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
		return steeringK * rudderPos * c.velSquaredLength * aoaScale;
	}

	void propagateInTime(float dt)
	{
		float targetRudderPos = sgn(error);
		if (fabs(error) < 0.4f)
			targetRudderPos = clamp(Kp * error + Kd * errorDeriv, -1.0f, 1.0f);
		rudderPos = cmove(rudderPos, targetRudderPos, posChangeSpeed, dt);
	}
}
