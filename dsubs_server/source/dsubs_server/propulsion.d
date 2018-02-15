module dsubs_server.propulsion;

import dsubs_common.math;

import dsubs_server.damage;
import dsubs_server.common;
import dsubs_server.dynamics;


/// module that is responsible for forward\backwards thrust
abstract class Propulsor: IForce
{
	Transform2D transform;
	string prototypeName;

	float rotSpd = 0.0f;		// [-1.0, 1.0]
	float targetRotSpd = 1.0f;	// [-1.0, 1.0]
}

/// simple propulsor with linear thrust law
class BasicPropulsor: Propulsor
{
	float rotAcceleration = 0.34f;	/// how fast rotSpd can change
	float posThrustK = 0.0f;
	float negThrustK = 0.0f;

	vec2d getForce(const SubmergedRigidBody b, ref const Kinematics c)
	{
		double absThrust = rotSpd * (rotSpd >= 0.0f ? posThrustK : negThrustK);
		//trace("absThrust: ", absThrust, " posThrustK: ", posThrustK);
		//trace("thrust: ", transform.wforward * absThrust);
		return transform.wforward * absThrust;
	}

	double getTorque(const SubmergedRigidBody b, ref const Kinematics c)
	{
		return 0.0;
	}

	void propagateInTime(float dt)
	{
		//trace(rotSpd, " ", targetRotSpd);
		rotSpd = cmove(rotSpd, targetRotSpd, rotAcceleration, dt);
		//trace(rotSpd);
	}
}


abstract class Rudder: IForce
{
	Transform2D transform;

	/// target course
	float targetCourse = 0.0f;
	float rudderPos = 0.0f;
}

/// PD-controlled rudder
class BasicRudder: Rudder
{
	float posChangeSpeed = 1.0f;

	/// actual torque power
	float steeringK = 0.0f;

	// PD controller gains
	float Kp = 2.0;
	float Kd = -10.0;

	private float error = 0.0;
	private float errorDeriv = 0.0;

	vec2d getForce(const SubmergedRigidBody b, ref const Kinematics c)
	{
		// TODO: there should be small lift here but fuck it
		return vec2d(0.0, 0.0);
	}

	double getTorque(const SubmergedRigidBody b, ref const Kinematics c)
	{
		error = angleDist(targetCourse, transform.wrotation);
		errorDeriv = c.angVel;
		double absSin = fabs(sin(c.AoA));
		double aoaScale = 1.0 - fmin(0.95, 2.0 * absSin);
		return steeringK * rudderPos * c.velSquaredLength * aoaScale;
	}

	void propagateInTime(float dt)
	{
		float targetRudderPos = Kp * error + Kd * errorDeriv;
		rudderPos = cmove(rudderPos, targetRudderPos, posChangeSpeed, dt);
	}
}
