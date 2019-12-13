module dsubs_server.dynamics;

import std.algorithm;
import std.array;

import dsubs_common.containers.array;
import dsubs_common.math;
import dsubs_common.containers.quadtree;
import dsubs_common.event;

import dsubs_server.common;
import dsubs_server.vessel;


struct HydroForceModel
{
	// drag model: drag = (Cd0 * v + Cd1 * v^2) * (1 + Cda * abs(sin(AoA)))
	double Cd0 = 0.0;
	double Cd1 = 0.0;
	double Cda = 0.0;
	// rotational drag model: torque = -angV^2 * Cr1 - angV * Cr0
	double Cr0 = 0.0;
	double Cr1 = 0.0;
	// lift model: lift = v^2 * sin(2 * AoA) * Cl
	double Cl = 0.0;
	// torque model: torque = v^2 * Cm * sin(AoA)
	// Assumes stability with negative Cm.
	double Cm = 0.0;

	/// magnitude of drag force
	double drag(double velMagn, double velSqr, double aoa)
	{
		return (Cd0 * velMagn + Cd1 * velSqr) * (1.0 + fabs(sin(aoa)) * Cda);
	}

	/// magnitude of torque
	double torque(double velSqr, double angVel, double aoa)
	{
		double drag_tq = - sgn(angVel) * angVel * angVel * Cr1 - angVel * Cr0;
		double stabil_tq = velSqr * sin(aoa) * Cm;
		return drag_tq + stabil_tq;
	}

	/// magnitude of lift, always towards left hand
	double lift(double velSqr, double aoa)
	{
		return velSqr * sin(2.0 * aoa) * Cl;
	}
}

/// Calculate Cl, required to achieve turning radius on AoA with a mass
double calcClForTurningRadius(double aoa, double rad, double mass)
{
	return mass / sin(2.0 * aoa) / rad;
}


/// snapshot of kinematic parameters of a rigid body
struct Kinematics
{
	vec2d pos = vec2d(0.0, 0.0);
	vec2d vel = vec2d(0.0, 0.0);
	double angVel = 0.0;
	double rotation = 0.0;

	Kinematics opBinary(string op)(Kinematics rhs)
		if (op == "+")
	{
		Kinematics res = this;
		res.pos = pos + rhs.pos;
		res.vel = vel + rhs.vel;
		res.angVel = angVel + rhs.angVel;
		res.rotation = rotation + rhs.rotation;
		return res;
	}

	Kinematics opBinary(string op)(double rhs)
		if (op == "*")
	{
		Kinematics res = this;
		res.pos = pos * rhs;
		res.vel = vel * rhs;
		res.angVel = angVel * rhs;
		res.rotation = rotation * rhs;
		return res;
	}

	Kinematics opBinaryRight(string op)(double rhs)
		if (op == "*")
	{
		return this.opBinary!op(rhs);
	}

	// cache for popular stuff
	double AoA;		/// drift angle
	double velLength;
	double velSquaredLength;
	double velRotation;
	double progradeSpeed;	/// dot(forward, vel)
	vec2d velNormalized;
	vec2d velLeft;
	vec2d forward;
	vec2d left;

	void updateCache()
	{
		AoA = angleDist(rotation, courseAngle(vel));
		if (isNaN(AoA))
			AoA = 0.0;
		assert(!isNaN(AoA));
		velSquaredLength = vel.squaredLength;
		assert(!isNaN(velSquaredLength));
		velLength = sqrt(velSquaredLength);
		assert(!isNaN(velLength));
		if (velLength > 0.0)
		{
			velNormalized = vel.normalized;
			velRotation = courseAngle(velNormalized);
			if (isNaN(velRotation))
				velRotation = rotation;
			assert(!isNaN(velRotation));
		}
		else
		{
			velNormalized = vec2d(0.0, 1.0);
			velRotation = 0.0;
		}
		double velLeftRotation = velRotation + PI_2;
		assert(!isNaN(velLeftRotation));
		velLeft = vec2d(-sin(velLeftRotation), cos(velLeftRotation));
		forward = vec2d(-sin(rotation), cos(rotation));
		double leftRotation = rotation + PI_2;
		left = vec2d(-sin(leftRotation), cos(leftRotation));
		progradeSpeed = dot(vel, forward);
		//trace("updated kinematics: ", this);
	}
}


/// RK-like methods require to evaluate forces on different times between
/// integration snaps. ForceSnapshot allows integrator to reset the internal state of
/// the force to the point of 0.0 time.
struct ForceSnapshot
{
	float state;
}


/// Some external source of force and torque, that can act on RigidBody.
/// Force is assumed to be stateful and keeps track of time.
interface IForce
{
	/// get translational force component.
	vec2d getForce(const RigidBody b, const ref Kinematics c);

	/// get this force resulting torque.
	double getTorque(const RigidBody b, const ref Kinematics c);

	/// if there is some timing logic inside IForce, move forward in time.
	void propagateInTime(float dt);

	ForceSnapshot save();

	void rollback(ForceSnapshot snap);
}


/// Rigid body for 2d dsubs world
final class RigidBody: PhysicalEntity
{
	Kinematics kinet;
	double moi;
	double mass;
	HydroForceModel hydroModel;
	Vessel vesselOwner;	/// may be null

	// TODO: maybe tree needs double precision as well.
	private QuadTree!(RigidBody).LeafNode* spacialTreeNode;

	IForce[] forces;

	this(Transform2D t)
	{
		transform = t;
		updateFromTransform();
	}

	/// update kinematics position and rotation from this body's transform
	void updateFromTransform()
	{
		kinet.pos = transform.wposition;
		kinet.rotation = transform.wrotation;
		kinet.updateCache();
		//trace(kinet);
	}

	private void updateSpacialTreeNode()
	{
		spacialTreeNode.rect = Rectangle(
			transform.wposition.to!vec2f - vec2f(50, 50),
			vec2f(100, 100));
	}

	/// physics update step, RK2
	override void integrate(float dt)
	{
		Kinematics kinet1 = kinet;
		vec2d linAcc1 = linAcc(kinet);
		double rotAcc1 = rotAcc(kinet);
		kinet1.pos += dt * kinet.vel;
		kinet1.rotation += dt * kinet.angVel;
		kinet1.vel += dt * linAcc1;
		kinet1.angVel += dt * rotAcc1;

		foreach (force; forces)
			force.propagateInTime(dt * 0.5f);

		Kinematics kinetMiddle = 0.5 * (kinet + kinet1);
		kinetMiddle.updateCache();
		Kinematics kinet2 = kinet;
		vec2d linAcc2 = linAcc(kinetMiddle);
		double rotAcc2 = rotAcc(kinetMiddle);
		kinet2.pos += dt * kinetMiddle.vel;
		kinet2.rotation += dt * kinetMiddle.angVel;
		kinet2.vel += dt * linAcc2;
		kinet2.angVel += dt * rotAcc2;

		foreach (force; forces)
			force.propagateInTime(dt * 0.5f);

		kinet = kinet2;
		kinet.updateCache();
		// update transform
		transform.position = kinet.pos;
		transform.rotation = kinet.rotation;
	}

	private vec2d linAcc(const ref Kinematics c)
	{
		vec2d resultForce = vec2d(0.0, 0.0);
		foreach (force; forces)
		{
			resultForce += force.getForce(this, c);
			assert(!isNaN(resultForce.x) && !isNaN(resultForce.y),
				"NaN force from " ~ force.to!string);
		}
		resultForce -= hydroModel.drag(c.velLength, c.velSquaredLength, c.AoA) * c.velNormalized;
		resultForce += hydroModel.lift(c.velSquaredLength, c.AoA) * c.velLeft;
		assert(mass > 0.0);
		return resultForce / mass;
	}

	private double rotAcc(const ref Kinematics c)
	{
		double resultTorque = 0.0;
		foreach (force; forces)
			resultTorque += force.getTorque(this, c);
		resultTorque += hydroModel.torque(c.velSquaredLength, c.angVel, c.AoA);
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


/// Set of rigid bodies that is simulated
final class PhysicalEnv
{
	private
	{
		PhysicalEntity[] m_entities;
		QuadTree!RigidBody m_spacialTree;
	}

	this()
	{
		m_spacialTree = new QuadTree!(RigidBody)(10000.0f, 200.0f);
	}

	void registerEntity(PhysicalEntity e)
	{
		synchronized(this)
		{
			m_entities ~= e;
			RigidBody rb = cast(RigidBody) e;
			if (rb)
				rb.spacialTreeNode = m_spacialTree.addLeaf(
					Rectangle(rb.transform.wposition.to!vec2f - vec2f(50, 50),
						vec2f(100, 100)),
					rb);
		}
	}

	void unregisterEntity(PhysicalEntity e)
	{
		synchronized(this)
		{
			m_entities.removeFirstUnstable(e);
			RigidBody rb = cast(RigidBody) e;
			if (rb && rb.spacialTreeNode)
			{
				m_spacialTree.removeLeaf(rb.spacialTreeNode);
				rb.spacialTreeNode = null;
			}
		}
	}

	/// clean the container
	void clean()
	{
		m_entities.length = 0;
		m_spacialTree.clear();
	}

	/// perform physics update for all entities
	void integratePBodies(float fwd = 1.0f, float maxDt = 0.25f)
	{
		long stepCount = lrint(fwd / maxDt);
		assert(stepCount > 0);
		float dt = fwd / stepCount;
		foreach (i, ref PhysicalEntity entity; Globals.taskPool.parallel(m_entities, 4))
		{
			for (int j = 0; j < stepCount; j++)
			{
				entity.integrate(dt);
			}
		}
		// quadtree is not thread-safe
		foreach (entity; m_entities)
		{
			RigidBody rb = cast(RigidBody) entity;
			if (rb)
				rb.updateSpacialTreeNode();
		}
	}

	RigidBody[] findRigidBodiesInCirlce(vec2f center, float searchRadius) const
	{
		QuadTree!(RigidBody).LeafNode*[] leafs;
		m_spacialTree.findCentersInCircle(center, searchRadius, leafs, true);
		if (leafs.length == 0)
			return null;
		return leafs.map!(l => l.payload).array;
	}
}