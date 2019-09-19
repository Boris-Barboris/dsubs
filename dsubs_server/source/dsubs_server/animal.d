module dsubs_server.animal;

import std.algorithm.comparison: max;

import dsubs_common.containers.array;
import dsubs_common.math;

import dsubs_sound.common: GLOBAL_SRATE, uniform;
import dsubs_sound.soundsource;
import dsubs_sound.activesonar: Reflector, ReflectorPrototype;

import dsubs_server.common;
import dsubs_server.dynamics;
import dsubs_server.acoustics;


final class Animal
{
	private
	{
		Transform2D m_transform;
		RigidBody m_rigidBody;
		AnimalFactory m_factory;
		vec2d m_destination = vec2d(0, 0);
		usecs_t m_nextSoundStart;
		Reflector m_reflector;
		vec2d m_velocity = vec2d(0, 0);
		PrerecordedSoundSource m_currentSoundSource;
	}

	@property Transform2D transform() { return m_transform; }

	@property void destination(vec2d rhs)
	{
		m_destination = rhs;
		double speed = uniform!("(]")(0.1, m_factory.maxSpeed);
		m_velocity = speed * (m_destination - m_transform.wposition).normalized;
		m_rigidBody.kinet.vel = m_velocity;
	}

	this(AnimalFactory f)
	{
		m_transform = new Transform2D();
		m_rigidBody = new RigidBody(m_transform);
		m_factory = f;
	}

	usecs_t generateNextSoundStart()
	{
		return Globals.sim.worldTime + max(0, uniform!"[]"(
			m_factory.meanSoundPause - m_factory.soundPauseVariance,
			m_factory.meanSoundPause + m_factory.soundPauseVariance));
	}

	void onPostKinematics(usecs_t dt)
	{
		if (Globals.sim.worldTime >= m_nextSoundStart)
		{
			// spawn new sound source
			size_t sourceIdx = uniform!"[)"(0, m_factory.randomSounds.length);
			// info("starting whale song");
			m_currentSoundSource = new PrerecordedSoundSource(m_transform,
				m_factory.randomSounds[sourceIdx]);
			Globals.acous.registerSource(m_currentSoundSource);
			m_nextSoundStart =
				(1e6 * m_currentSoundSource.totalSamples / GLOBAL_SRATE).to!usecs_t +
				generateNextSoundStart();
		}
	}

	void register()
	{
		Globals.animals.registerEntity(this);
		m_rigidBody.updateFromTransform();
		m_nextSoundStart = generateNextSoundStart();
		Globals.phys.registerEntity(m_rigidBody);
		Globals.acous.registerReflector(m_reflector);
	}

	void shutdown()
	{
		Globals.acous.unregisterReflector(m_reflector);
		Globals.phys.unregisterEntity(m_rigidBody);
		if (m_currentSoundSource && !m_currentSoundSource.finished)
			Globals.acous.unregisterSource(m_currentSoundSource);
		Globals.animals.unregisterEntity(this);
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

	void clean()
	{
		Animal[] entities = m_entities;
		foreach(e; entities)
			e.shutdown();
		assert(m_entities.length == 0, "animal leak");
	}
}


final class AnimalFactory
{
	PrerecordedSoundPrototype[] randomSounds;
	usecs_t meanSoundPause;
	usecs_t soundPauseVariance;
	float maxSpeed = 0.0;
	ReflectorPrototype reflprot;
	float mass;

	final Animal build() const
	{
		Animal res = new Animal(cast() this);
		res.m_rigidBody.mass = mass;
		res.m_rigidBody.moi = 1.0f;
		res.m_reflector = new Reflector(res.m_transform, reflprot);
		return res;
	}
}