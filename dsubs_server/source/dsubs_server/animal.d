module dsubs_server.animal;

import std.algorithm.comparison: max;

import dsubs_common.containers.array;
import dsubs_common.math;

import dsubs_sound.common: uniform;
import dsubs_sound.soundsource;
import dsubs_sound.activesonar: Reflector, ReflectorPrototype;

import dsubs_server.common;
import dsubs_server.dynamics;
import dsubs_server.simulator;
import dsubs_server.acoustics;
import dsubs_server.vessel;


final class Animal: Killable, IHasTransform, IHasRigidBody
{
	private
	{
		string m_name;
		Transform2D m_transform;
		RigidBody m_rigidBody;
		AnimalFactory m_factory;
		vec2d m_destination = vec2d(0, 0);
		Reflector m_reflector;
		vec2d m_velocity = vec2d(0, 0);
		Jukebox m_jukebox;
	}

	@property RigidBody rigidBody() { return m_rigidBody; }

	@property string name() const { return m_name; }

	@property string species() const { return m_factory.species; }

	@property Transform2D transform() { return m_transform; }

	@property void destination(vec2d rhs)
	{
		m_destination = rhs;
		double speed = uniform!("(]")(0.1, m_factory.maxSpeed);
		m_velocity = speed * (m_destination - m_transform.wposition).normalizedz;
		// it will swim in the direction of destination, overpass it and
		// continue forever. Drag of m_rigidBody us zero, so this works.
		m_rigidBody.kinet.vel = m_velocity;
	}

	@property bool arrivedAtDestination()
	{
		return (transform.wposition - m_destination).length < 30.0f;
	}

	@property ref PrerecordedSoundPrototype[] randomSounds()
	{
		return m_jukebox.randomSounds;
	}

	@property ref JukeboxSoundTimings soundTimings()
	{
		return m_jukebox.soundTimings;
	}

	this(AnimalFactory f)
	{
		m_transform = new Transform2D();
		m_rigidBody = new RigidBody(m_transform);
		m_rigidBody.owner = this;
		m_factory = f;
		m_jukebox = new Jukebox(this, m_transform);
	}

	void onPostKinematics(usecs_t dt)
	{
		m_jukebox.onSimUpdate();
	}

	void register(Simulator sim)
	{
		registerSimulator(sim);
		m_jukebox.setSimulator(sim);
		m_jukebox.initNextSoundStart();
		sim.animals.registerEntity(this);
		m_rigidBody.updateFromTransform();
		sim.phys.registerEntity(m_rigidBody);
		sim.acous.registerReflector(m_reflector);
	}

	void shutdown()
	{
		simulator.acous.unregisterReflector(m_reflector);
		simulator.phys.unregisterEntity(m_rigidBody);
		m_jukebox.shutdown();
		simulator.animals.unregisterEntity(this);
	}

}


final class AnimalCollection
{
	private
	{
		Animal[] m_entities;
	}

	@property Animal[] entities() { return m_entities; }

	void registerEntity(Animal e)
	{
		synchronized(this)
		{
			m_entities ~= e;
		}
	}

	void unregisterEntity(Animal e)
	{
		synchronized(this)
		{
			m_entities.removeFirstUnstable(e);
		}
	}

	void postKinematics(usecs_t dt)
	{
		foreach (animal; Globals.taskPool.parallel(m_entities, 8))
			animal.onPostKinematics(dt);
	}

	void shutdownAll()
	{
		Animal[] animalsToRemove = m_entities.dup;
		foreach (a; animalsToRemove)
			a.shutdown();
		assert(m_entities.length == 0, "animal leak");
	}

	void clean()
	{
		m_entities.length = 0;
	}

	void collectDeadAnimals()
	{
		Animal[] deadAnimals;
		foreach (animal; m_entities)
		{
			if (animal.dead)
				deadAnimals ~= animal;
		}
		foreach (a; deadAnimals)
			a.shutdown();
	}
}



final class AnimalFactory
{
	/// Copied into the animal, so they can be modified on per-animal basis
	PrerecordedSoundPrototype[] randomSounds;
	JukeboxSoundTimings soundTimings;
	float maxSpeed = 0.0;
	ReflectorPrototype reflprot;
	float mass;
	string species;

	final Animal build(string name)
	{
		Animal res = new Animal(cast() this);
		res.m_jukebox.randomSounds = randomSounds.dup;
		res.m_jukebox.soundTimings = soundTimings;
		res.m_name = name;
		res.m_rigidBody.mass = mass;
		res.m_rigidBody.moi = 1.0f;
		res.m_reflector = new Reflector(res.m_transform, reflprot);
		res.m_reflector.owner = res;
		return res;
	}
}