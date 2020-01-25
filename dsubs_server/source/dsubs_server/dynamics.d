module dsubs_server.dynamics;

import std.algorithm;
import std.array;

// "lflags": ["/home/boris/src/dsubs/dsubs_server/libopenblas"],
// import mir.ndslice: magic, repeat, as, slice;
// import lubeck: mtimes;

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


/// Point on the wire that has mass. Drag force is applied to it.
/// Wire is always bound to some fixed point by it's end.
struct WirePoint
{
	/// velocity in global reference frame.
	vec2d vel = vec2f(0.0f, 0.0f);
	/// position in global reference frame.
	vec2d pos = vec2f(0.0f, 0.0f);
}

private enum float PREFERRED_SEGMENT_LENGTH = 20.0f;
private enum float WINCH_EXTEND_SPD_FACTOR = 0.9f;


struct AttachedWirePrototype
{
	float maxLength = 0.0f;
	int sensorTransformPoint = 1;
	float winchSpeed = 5.0f;
	float pointCD0 = 2e-2f;
	float pointCD1 = 2e-2f;
	float pointMass = 0.2f;
}

/// Extendable/retractable wire that is attached to rigid body.
final class AttachedWire: IForce
{
	private
	{
		/// Head of the array is the tail of the wire. Tail is the first point after the attachment.
		WirePoint[] m_points;
		/// Attachment point on the rigid body.
		Transform2D m_attachTransform;
		/// Transform, created for the sensor.
		Transform2D m_sensorTransform;
		/// index of the point that is bound to m_sensorTransform.
		size_t m_sensorPointIdx;
		/// Body that owns the m_attachTransform.
		RigidBody m_rigidBody;
		/// Total length of the wire on full extention.
		float m_maxLength = 0.0f;

		/// Maximum distance between two m_points.
		float m_segmentLength = 0.0f;
		/// Equals to maximum number of wire m_points that are dangling behind
		/// the attachment point. m_maxSegmentCount * m_segmentLength is effectively
		/// the maximum extension length of the wire.
		int m_maxSegmentCount;
		/// The length of first segment. All other segments are fully extended to their 'm_segmentLength'.
		float m_firstSegmentLength = 0.0f;
		float m_currentTotalLength = 0.0f;
		/// Captains declare the desired total length of the wire and the winch obeys.
		float m_desiredLength = 0.0f;
		float m_winchSpeed;

		// point hydrodynamics drag gains.
		float m_pointCD0;
		float m_pointCD1;
		// point mass
		float m_pointMass;

		/// force that the wire is applying to attachment point.
		vec2d m_lastAttachForce = vec2d(0, 0);
	}

	@property Transform2D sensorTransform() { return m_sensorTransform; }

	this(Transform2D transform, RigidBody rigidBody, AttachedWirePrototype proto)
	{
		m_attachTransform = transform;
		m_sensorPointIdx = proto.sensorTransformPoint.to!size_t;
		m_sensorTransform = new Transform2D();
		m_rigidBody = rigidBody;
		maxLength = proto.maxLength;
		m_winchSpeed = proto.winchSpeed;
		m_pointCD0 = proto.pointCD0;
		m_pointCD1 = proto.pointCD1;
		m_pointMass = proto.pointMass;
	}

	@property bool sensorTransformValid() const { return m_points.length > m_sensorPointIdx; }

	@property vec2d sensorPointVel() const
	{
		if (sensorTransformValid)
			return m_points[m_sensorPointIdx].vel;
		else
			return m_rigidBody.kinet.vel;
	}

	/// Try to simulate transform for a hydrophone. Returns false if the wire
	/// is too short or too compact.
	private bool getPointPosTangentRot(size_t pointIdx, out vec2d pos, out double rot)
	{
		if (pointIdx >= m_points.length)
			return false;
		pos = m_points[pointIdx].pos;
		vec2d tangentPos;
		if (pointIdx + 1 == m_points.length)
			tangentPos = m_attachTransform.wposition;
		else
			tangentPos = m_points[pointIdx + 1].pos;
		if (pos == tangentPos)
			return true;
		rot = courseAngle(pos - tangentPos);
		assert(!isNaN(rot));
		return true;
	}

	void updateSensorTransform()
	{
		vec2d pos;
		double rot;
		if (getPointPosTangentRot(m_sensorPointIdx, pos, rot))
		{
			m_sensorTransform.position = pos;
			// we do not mutate rotation if it cannot be effectively computed
			if (!isNaN(rot))
				m_sensorTransform.rotation = rot;
		}
		else
		{
			m_sensorTransform.position = m_attachTransform.wposition;
			m_sensorTransform.rotation = clampAnglePi(m_attachTransform.wrotation + PI);
		}
	}

	@property Transform2D attachTransform() { return m_attachTransform; }

	@property const(WirePoint)[] points() const { return m_points; }

	@property float maxLength() const { return m_maxLength; }

	@property void maxLength(float rhs)
	{
		assert(isNormal(rhs));
		m_maxLength = rhs;
		m_maxSegmentCount = ceil(m_maxLength / PREFERRED_SEGMENT_LENGTH).lrint.to!int;
		m_segmentLength = m_maxLength / m_maxSegmentCount;
	}

	@property float desiredLength() const { return m_desiredLength; }

	@property void desiredLength(float rhs)
	{
		enforce(!isNaN(rhs) && !isInfinity(rhs), "nan or infinity");
		enforce(rhs >= 0.0f && rhs <= m_maxLength, "desiredLength out of bounds");
		m_desiredLength = rhs;
	}

	/// Update length characteristics and point count as if 'dt' seconds have passed.
	void updateTotalLength(float dt)
	{
		size_t currentSegments = m_points.length;
		float activeWinchSpeed = m_winchSpeed;
		if (m_desiredLength > m_currentTotalLength)
		{
			// we limit unwinding speed for slow-moving sub.
			double rbSpeed = m_rigidBody.kinet.velLength;
			activeWinchSpeed = min(activeWinchSpeed, WINCH_EXTEND_SPD_FACTOR * rbSpeed);
		}
		m_currentTotalLength = cmove(m_currentTotalLength, m_desiredLength, activeWinchSpeed, dt);
		size_t nextSegments = ceil(m_currentTotalLength / m_segmentLength).lrint.to!size_t;
		m_firstSegmentLength = m_currentTotalLength - (nextSegments - 1) * m_segmentLength;
		// now we resize m_points array if needed
		m_points.length = nextSegments;
		if (nextSegments > currentSegments)
		{
			// new m_points are to be spawned. We place them on the attachment point.
			vec2d attachPos = m_attachTransform.wposition;
			// we need to calculate the ejection speed
			vec2d attachVel = m_rigidBody.fixedPointVelocity(attachTransform);
			vec2d ejectionVel = attachVel - m_attachTransform.wforward * activeWinchSpeed;
			for (size_t i = currentSegments; i < nextSegments; i++)
			{
				m_points[i].pos = attachPos;
				m_points[i].vel = ejectionVel;
			}
		}
	}

	/// simulation step for the wire, must be ran after rigid body update.
	void simulate(float dt)
	{
		assert(isNormal(m_pointMass));
		// first step is to update velocities
		foreach (ref WirePoint point; m_points)
		{
			double velSqr = point.vel.squaredLength;
			// the only external force that is acting on the m_points is water drag
			if (velSqr > 0.0f)
			{
				double velMagn = sqrt(velSqr);
				double dragMagn = m_pointCD0 * velMagn + m_pointCD1 * velSqr;
				double deltaVel = dt * dragMagn / m_pointMass;
				assert(isNormal(deltaVel));
				// assert that the system is not too stiff for us.
				assert(deltaVel < velMagn);
				point.vel -= deltaVel * point.vel.normalized;
			}
		}
		// we now give a first estimation of new point positions
		vec2d[] newPositions;
		newPositions.length = m_points.length;
		for (size_t i = 0; i < newPositions.length; i++)
			newPositions[i] = m_points[i].pos + m_points[i].vel * dt;

		// simple constraint projection loop that moves new positions by the straigt line
		// to the allowed position.
		for (size_t i = newPositions.length; i > 0; i--)
		{
			size_t j = i - 1;
			vec2d fixedPos;
			double distanceLimit;
			if (i == newPositions.length)
			{
				// first point directly attached by one segment to rigid body.
				fixedPos = m_attachTransform.wposition;
				distanceLimit = m_firstSegmentLength;
			}
			else
			{
				fixedPos = newPositions[i];
				distanceLimit = m_segmentLength;
			}
			assert(!isNaN(distanceLimit));
			double distance = (fixedPos - newPositions[j]).length;
			assert(!isNaN(distance));
			if (distance > distanceLimit)
			{
				// project
				vec2d delta = (1.0 - distanceLimit / distance) *
					(fixedPos - newPositions[j]);
				assert(!isNaN(delta.x));
				assert(!isNaN(delta.y));
				newPositions[j] = newPositions[j] + delta;
			}
		}

		// update m_points and calculate attach force
		m_lastAttachForce = vec2d(0, 0);
		double attachForceMagn = 0.0;
		foreach (i, ref point; m_points)
		{
			vec2d estimatedVel = point.vel;
			point.vel = (newPositions[i] - point.pos) / dt;
			vec2d deltaVel = point.vel - estimatedVel;
			// deltaVel.length / dt is acceleration, F = ma
			attachForceMagn += deltaVel.length / dt * m_pointMass;
			// deltaVel is the velocity change that was caused by rigid body's pull.
			point.pos = newPositions[i];
			assert(!isNaN(point.pos.x));
			assert(!isNaN(point.pos.y));
			if (i == m_points.length - 1)
				m_lastAttachForce = attachForceMagn *
					(point.pos - m_attachTransform.wposition).normalizedz;
		}
		assert(!isNaN(m_lastAttachForce.x));
		assert(!isNaN(m_lastAttachForce.y));
	}

	// IForce stuff
	vec2d getForce(const RigidBody b, const ref Kinematics c)
	{
		return m_lastAttachForce;
	}

	/// get this force resulting torque.
	double getTorque(const RigidBody b, const ref Kinematics c)
	{
		return b.getForcesTorque(m_lastAttachForce, m_attachTransform);
	}

	/// if there is some timing logic inside IForce, move forward in time.
	void propagateInTime(float dt) {}

	ForceSnapshot save() { return ForceSnapshot(0.0); }

	void rollback(ForceSnapshot snap) {}
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
	/// get total force.
	vec2d getForce(const RigidBody b, const ref Kinematics c);

	/// get this force resulting torque. Force choses it's application point, or
	/// lack of it. Pure-torque dynamic effect that is effectively a combination of forces
	/// can be implemented this way.
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
	/// wires that are attached to this body
	AttachedWire[] wires;

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
		foreach (AttachedWire wire; wires)
			wire.updateSensorTransform();
		//trace(kinet);
	}

	/// Return global velocity of the point that is fixed on rigid body's surface and is represented by child
	/// transform.
	vec2d fixedPointVelocity(Transform2D atTransform)
	{
		vec2d deltaPos = atTransform.wposition - transform.wposition;
		vec3d deltaPos3d = vec3d(deltaPos.x, deltaPos.y, 0.0);
		vec3d angVel3d = vec3d(0.0, 0.0, kinet.angVel);
		vec3d linearVel3d = cross(angVel3d, deltaPos3d);
		vec2d planarVel = vec2d(linearVel3d.x, linearVel3d.y);
		return planarVel + kinet.vel;
	}

	double getForcesTorque(vec2d force, Transform2D atTransform) const
	{
		vec2d posVec = atTransform.wposition - kinet.pos;
		vec3d torque = cross(vec3d(posVec.x, posVec.y, 0.0), vec3d(force.x, force.y, 0.0));
		return torque.z;
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
		foreach (AttachedWire wire; wires)
			wire.updateTotalLength(dt);

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

		foreach (AttachedWire wire; wires)
		{
			wire.simulate(dt);
			wire.updateSensorTransform();
		}
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
		foreach (wire; wires)
		{
			resultForce += wire.getForce(this, c);
			assert(!isNaN(resultForce.x) && !isNaN(resultForce.y),
				"NaN force from " ~ wire.to!string);
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
		foreach (wire; wires)
		{
			resultTorque += wire.getTorque(this, c);
			assert(!isNaN(resultTorque), "NaN torque from " ~ wire.to!string);
		}
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