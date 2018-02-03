module dsubs_server.propulsion;

import dsubs_common.math;

import dsubs_server.damage;
import dsubs_server.dynamics;


class BasicPropulsor: IForce
{
	Transform2D transform;

	float rotSpd = 0.0f;		// [-1.0, 1.0]
	float targetRotSpd = 0.0f;	// [-1.0, 1.0]
	float rotAcceleration = 0.34f;	/// how fast rotSpd can change
	float posThrustK = 0.0f;
	float negThrustK = 0.0f;

	vec2d getForce(const SubmergedRigidBody b, const ref Kinematics c)
	{
		double absThrust = rotSpd * (rotSpd >= 0.0f ? posThrustK : negThrustK);
		return transform.forward * absThrust;
	}

	double getTorque(const SubmergedRigidBody b, const ref Kinematics c)
	{
		// TODO? actual torque if transform is not on symmetry axis
		return 0.0;
	}

	void propagateInTime(double dt)
	{
		rotSpd = cmove(rotSpd, targetRotSpd, rotAcceleration, dt);
	}
}


class Rudder: IForce
{
	double targetCourse = 0.0;
	float rudderPos = 0.0f;
	float posChangeSpeed = 0.5f;
	float steeringK = 0.0f;

	// PD controller gains
	double Kp = 1.0;
	double Kd = -0.1;

	private double error = 0.0;
	private double errorDeriv = 0.0;

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

	void propagateInTime(double dt)
	{
		float targetRudderPos = Kp * error + Kd * errorDeriv;
		rudderPos = cmove(rudderPos, targetRudderPos, posChangeSpeed, dt);
	}
}
