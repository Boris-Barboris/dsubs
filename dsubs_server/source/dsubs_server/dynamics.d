module dsubs_server.dynamics;

import std.algorithm;
import std.math;
import core.sync.mutex;

import dsubs_common.containers.array;
import dsubs_common.math;

import dsubs_server.threading;


struct HydroForceModel
{
	// drag model: drag = v^2 * (Cd0 + Cd1 * sin(AoA))
	double Cd0;
	double Cd1;
	// rotational drag model: torque = -angV^2 * Cr
	double Cr;
	// lift model: lift = v^2 * sin(2 * AoA) * Cl
	double Cl;

	double drag(double velSqr, double aoa)
	{
		return velSqr * (Cd0 + sin(aoa) * Cd1);
	}

	double torque(double angVel)
	{
		return - sgn(angVel) * angVel * angVel * Cr;
	}

	double lift(double velSqr, double aoa)
	{
		return velSqr * sin(2.0 * aoa) * Cl;
	}
}


struct Kinematics
{
	vec2d pos = vec2d(0.0, 0.0);
	vec2d vel = vec2d(0.0, 0.0);
	double angVel = 0.0;
	double rotation = 0.0;

	// cache for popular stuff
	double AoA;
	double velLength;
	double velSquaredLength;
	double velRotation;
	vec2d velNormalized;
	vec2d velLeft;
	vec2d forward;
	vec2d left;

	void updateCache()
	{
		AoA = angleDist(rotation, courseAngle(vel));
		velSquaredLength = vel.squaredLength;
		velLength = sqrt(velSquaredLength);
		velNormalized = vel.normalized;
		velRotation = courseAngle(velNormalized);
		double velLeftRotation = velRotation + PI_2;
		velLeft = vec2d(-sin(velLeftRotation), cos(velLeftRotation));
		forward = vec2d(-sin(rotation), cos(rotation));
		double leftRotation = rotation + PI_2;
		left = vec2d(-sin(leftRotation), cos(leftRotation));
	}
}


/// Some external source of force and torque
interface IForce
{
	/// get this force vector at the time 't' since the beginning of this
	/// physics update.
	vec2d getForce(const SubmergedRigidBody b, const ref Kinematics c);

	/// get this force resulting torque at the time 't' since the beginning of this
	/// physics update.
	double getTorque(const SubmergedRigidBody b, const ref Kinematics c);

	/// if there is some timing logic inside IForce, move forward in time on dt.
	void propagateInTime(float dt);
}


/// Rigid body for 2d dsubs world
final class SubmergedRigidBody: PhysicalEntity
{
	Kinematics kinet;
	double moi;
	double mass;
	HydroForceModel hydroModel;

	IForce[] forces;

	this(Transform2D t)
	{
		kinet.pos = transform.position;
		kinet.rotation = transform.rotation;
	}

	/// physics update step, Eulers method
	override void integrate(float dt)
	{
		Kinematics nextKinet = kinet;
		vec2d linAcc1 = linAcc(kinet);
		double rotAcc1 = rotAcc(kinet);
		nextKinet.pos += dt * kinet.vel;
		nextKinet.rotation += dt * kinet.angVel;
		nextKinet.vel += dt * linAcc1;
		nextKinet.angVel += dt * rotAcc1;
		foreach (force; forces)
			force.propagateInTime(dt);
		kinet = nextKinet;
		kinet.updateCache();
		// update transform
		transform.position = kinet.pos;
		transform.rotation = kinet.rotation;
	}

	private vec2d linAcc(const ref Kinematics c)
	{
		vec2d resultForce = vec2d(0.0, 0.0);
		foreach (force; forces)
			resultForce += force.getForce(this, c);
		resultForce -= hydroModel.drag(c.velSquaredLength, c.AoA) * c.velNormalized;
		resultForce += hydroModel.lift(c.velSquaredLength, c.AoA) * c.velLeft;
		assert(mass > 0.0);
		return resultForce / mass;
	}

	private double rotAcc(const ref Kinematics c)
	{
		double resultTorque = 0.0;
		foreach (force; forces)
			resultTorque += force.getTorque(this, c);
		resultTorque += hydroModel.torque(c.angVel);
		assert(moi > 0.0);
		return resultTorque / moi;
	}
}


abstract class PhysicalEntity
{
	/// transform wich is updated on each integration step
	Transform2D transform;

	/// integrate this entity. Implies that the problem is embarassingly-parallel.
	void integrate(float dt);
}


/// list of all physical objects
private __gshared PhysicalEntity[] g_allBodies;
/// mutex that guards g_allBodies
private shared Mutex g_pbMut;

shared static this()
{
	g_allBodies.reserve(512);
	g_pbMut = new shared Mutex();
}

/// add new PhysicalEntity to global list
void registerPEntity(PhysicalEntity e)
{
	g_pbMut.lock();
	scope(exit) g_pbMut.unlock();
	g_allBodies ~= e;
}

/// remove PhysicalEntity from global list
void unregisterPEntity(PhysicalEntity e)
{
	g_pbMut.lock();
	scope(exit) g_pbMut.unlock();
	g_allBodies.removeFirstUnstable(e);
}

/// perform physics update for all pgysical bodies.
void integratePBodies(float fwd = 1.0f, float maxDt = 0.25f)
{
	long stepCount = lrint(fwd / maxDt);
	assert(stepCount > 0);
	float dt = fwd / stepCount;
	for (int i = 0; i < stepCount; i++)
	{
		foreach (i, ref entity; g_taskPool.parallel(g_allBodies, 8))
			entity.integrate(dt);
	}
}