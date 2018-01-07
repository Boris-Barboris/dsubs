module dsubs_server.dynamics;

import std.math;

import dsubs_common.math.transform;

import dsubs_server.rng;


struct HydroForceModel
{
	// drag model: drag = v^2 * (Cd0 + Cd1 * AoA)
	double Cd0;
	double Cd1;
	// rotational drag model: torque = -angV^2 * Cr
	double Cr;
	// lift model: lift = v^2 * cos(AoA) * Cl
	double Cl;

	double drag(double vel, double aoa)
	{
		return vel * vel * (Cd0 + aoa * Cd1);
	}

	double torque(double angVel)
	{
		return -angVel * angVel * Cr;
	}

	double lift(double vel, double aoa)
	{
		return vel * vel * cos(aoa) * Cl;
	}
}


/// Some external source of fource\torque
interface IForce
{
	/// get this force vector at the time 't' since the beginning of this
	/// physics update. Integrator will usually call this with t = 0, 0.25, 0.5, 0.75
	vec2d getForce(SubmergedRigidBody b, double t);

	/// get this force resulting torque at the time 't' since the beginning of this
	/// physics update.
	double getTorque(SubmergedRigidBody b, double t);
}

/// Rigid body for 2d dsubs world, bound to transform.
final class SubmergedRigidBody
{
	Transform2D t;
	vec2d vel;
	double angVel = 0.0;
	double moi;
	double mass;
	HydroForceModel forceModel;
	
	IForce[] forces;

	/// physics update step
	void integrate(double dt)
	{
		// RK4

	}

	/// angle of attack, radians
	double AoA()
	{

	}
}