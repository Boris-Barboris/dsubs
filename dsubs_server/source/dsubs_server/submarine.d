module dsubs_server.submarine;

import dsubs_common.math;

import dsubs_server.common;
import dsubs_server.dynamics;
import dsubs_server.player;
import dsubs_server.propulsion;


/// Server-side model of a submarine
final class Submarine
{
	Transform2D transform;
	SubmergedRigidBody rigidBody;

	// modules of various nature
	Rudder rudder;
	Propulsor propulsor;

	PlayerContext owner;

	/// name of the submarine type
	string prototypeName;

	/// creates transform and rigid body
	this(PlayerContext owner, string prototypeName)
	{
		assert(owner !is null);
		this.owner = owner;
		this.prototypeName = prototypeName;
		transform = new Transform2D();
		rigidBody = new SubmergedRigidBody(transform);
	}

	/// call this once after assigning all modules and initial values,
	/// to entangle all internal connections and register the submarine
	void bootstrap()
	{
		assert(rudder !is null);
		assert(propulsor !is null);
		rigidBody.forces = [cast(IForce) rudder, cast(IForce) propulsor];
		// bind module transforms to submarine itself
		rudder.transform = transform;
		propulsor.transform = transform;
		registerPEntity(rigidBody);
	}

	/// call this when removing this submarine from the physical world
	void shutdown()
	{
		unregisterPEntity(rigidBody);
		if (owner && owner.submarine is this)
			owner.submarine = null;
		owner = null;
	}

	/// set propulsor's target throttle
	void setThrottleFromUser(float target)
	{
		enforce(!isNaN(target), "Nan throttle");
		enforce(target <= 1.0f && target >= -1.0f, "Throttle not in [-1, 1] interval");
		propulsor.targetRotSpd = target;
	}

	/// set rudder's target course
	void setCourseFromUser(float target)
	{
		enforce(!isNaN(target), "Nan course");
		target = clampAngle(target - owner.coordRot);
		rudder.targetCourse = target;
	}
}