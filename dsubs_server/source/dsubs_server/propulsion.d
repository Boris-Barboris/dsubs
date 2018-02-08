module dsubs_server.propulsion;

import dsubs_common.math;

import dsubs_server.damage;
import dsubs_server.dynamics;


abstract class Propulsor: IForce
{
	Transform2D transform;

	float rotSpd = 0.0f;		// [-1.0, 1.0]
	float targetRotSpd = 0.0f;	// [-1.0, 1.0]
}

/// Simple propulsor class that pushes forward\backwards
class BasicPropulsor: Propulsor
{
	float rotAcceleration = 0.34f;	/// how fast rotSpd can change
	float posThrustK = 0.0f;
	float negThrustK = 0.0f;

	vec2d getForce(const SubmergedRigidBody b, ref const Kinematics c)
	{
		double absThrust = rotSpd * (rotSpd >= 0.0f ? posThrustK : negThrustK);
		return transform.wforward * absThrust;
	}

	double getTorque(const SubmergedRigidBody b, ref const Kinematics c)
	{
		return 0.0;
	}

	void propagateInTime(float dt)
	{
		rotSpd = cmove(rotSpd, targetRotSpd, rotAcceleration, dt);
	}
}

/// PD-controlled rudder
class BasicRudder: IForce
{
	float targetCourse = 0.0;
	float rudderPos = 0.0f;
	float posChangeSpeed = 0.5f;

	/// actual torque power
	float steeringK = 0.0f;

	// PD controller gains
	float Kp = 1.0;
	float Kd = -0.1;

	private float error = 0.0;
	private float errorDeriv = 0.0;

	vec2d getForce(const SubmergedRigidBody b, const ref Kinematics c)
	{
		return vec2d(0.0, 0.0);
	}

	double getTorque(const SubmergedRigidBody b, const ref Kinematics c)
	{
		error = targetCourse - c.rotation;
		errorDeriv = c.angVel;
		return steeringK * rudderPos * c.velSquaredLength;
	}

	void propagateInTime(float dt)
	{
		float targetRudderPos = Kp * error + Kd * errorDeriv;
		rudderPos = cmove(rudderPos, targetRudderPos, posChangeSpeed, dt);
	}
}
