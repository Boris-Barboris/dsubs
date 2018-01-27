module dsubs_server.propulsor;

import dsubs_common.math;

import dsubs_server.damage;
import dsubs_server.dynamics;


class BasicPropulsor: IForce
{
	Transform2D transform;

	float rotSpd = 0.0f;		// [-1.0, 1.0]
	float targetRotSpd = 0.0f;	// [-1.0, 1.0]
	float rotAcceleration = 0.5f;	/// how fast rotSpd can change
	float posThrustK = 0.0f;
	float negThrustK = 0.0f;

	vec2d getForce(const SubmergedRigidBody b, const ref Kinematics c)
	{
		double absThrust = rotSpd * (rotSpd >= 0.0f ? posThrustK : negThrustK);
		return transform.forward * absThrust;
	}

	double getTorque(const SubmergedRigidBody b, const ref Kinematics c)
	{
		return 0.0;
	}

	void propagateInTime(double dt)
	{
		rotSpd = cmove(rotSpd, targetRotSpd, rotAcceleration, dt);
	}
}

