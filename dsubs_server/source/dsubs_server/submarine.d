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

	/// creates transform and rigid body
	this(PlayerContext owner)
	{
		assert(owner !is null);
		this.owner = owner;
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
}