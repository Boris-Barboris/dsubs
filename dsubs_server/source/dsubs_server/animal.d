module dsubs_server.animal;

import std.algorithm.comparison: max;

import dsubs_common.containers.array;
import dsubs_common.math;

import dsubs_sound.common: GLOBAL_SRATE, uniform;
import dsubs_sound.soundsource;
import dsubs_sound.activesonar: Reflector, ReflectorPrototype;

import dsubs_server.common;
import dsubs_server.dynamics;
import dsubs_server.simulator;
import dsubs_server.acoustics;
import dsubs_server.vessel;


final class Animal: Killable, IHasTransform, IHasRidigBody
{
	private
	{
		string m_name;
		Transform2D m_transform;
		RigidBody m_rigidBody;
		AnimalFactory m_factory;
		vec2d m_destination = vec2d(0, 0);
		usecs_t m_nextSoundStart;
		Reflector m_reflector;
		vec2d m_velocity = vec2d(0, 0);
		PrerecordedSoundSource m_currentSoundSource;
		int songCounter;
		int currentSongLength;
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
		m_rigidBody.kinet.vel = m_velocity;
	}

	this(AnimalFactory f)
	{
		m_transform = new Transform2D();
		m_rigidBody = new RigidBody(m_transform);
		m_rigidBody.owner = this;
		m_factory = f;
	}

	usecs_t generateNextSoundStart()
	{
		usecs_t lowBound, highBound;
		if (songCounter == 0)
		{
			currentSongLength = uniform!"[]"(
				m_factory.songMinLength, m_factory.songMaxLength);
			lowBound = m_factory.meanSongPause - m_factory.songPauseVariance;
			highBound = m_factory.meanSongPause + m_factory.songPauseVariance;
		}
		else
		{
			lowBound = m_factory.intrasongPause;
			highBound = m_factory.intrasongPause;
		}
		songCounter++;
		if (songCounter >= currentSongLength)
			songCounter = 0;
		return simulator.worldTime + max(0, uniform!"[]"(lowBound, highBound));
	}

	void onPostKinematics(usecs_t dt)
	{
		if (simulator.worldTime >= m_nextSoundStart)
		{
			// spawn new sound source
			size_t sourceIdx = uniform!"[)"(0, m_factory.randomSounds.length);
			// info("starting whale song");
			m_currentSoundSource = new PrerecordedSoundSource(m_transform,
				m_factory.randomSounds[sourceIdx]);
			m_currentSoundSource.owner = this;
			simulator.acous.registerSource(m_currentSoundSource);
			m_nextSoundStart =
				(1e6 * m_currentSoundSource.totalSamples / GLOBAL_SRATE).to!usecs_t +
				generateNextSoundStart();
		}
	}

	void register(Simulator sim)
	{
		registerSimulator(sim);
		sim.animals.registerEntity(this);
		m_rigidBody.updateFromTransform();
		m_nextSoundStart = generateNextSoundStart();
		sim.phys.registerEntity(m_rigidBody);
		sim.acous.registerReflector(m_reflector);
	}

	void shutdown()
	{
		simulator.acous.unregisterReflector(m_reflector);
		simulator.phys.unregisterEntity(m_rigidBody);
		if (m_currentSoundSource && !m_currentSoundSource.finished)
			simulator.acous.unregisterSource(m_currentSoundSource);
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

	void clean()
	{
		Animal[] entities = m_entities;
		foreach(e; entities)
			e.shutdown();
		assert(m_entities.length == 0, "animal leak");
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
	PrerecordedSoundPrototype[] randomSounds;
	/// average pause between songs
	usecs_t meanSongPause;
	usecs_t songPauseVariance;
	float maxSpeed = 0.0;
	ReflectorPrototype reflprot;
	float mass;
	string species;
	// if randomSounds are short and you want to compose
	// a song from repeating the sounds, this is how many times
	// the animal should repeat it.
	int songMinLength = 1;
	int songMaxLength = 1;
	// pause between sounds inside one song.
	usecs_t intrasongPause;

	final Animal build(string name) const
	{
		Animal res = new Animal(cast() this);
		res.m_name = name;
		res.m_rigidBody.mass = mass;
		res.m_rigidBody.moi = 1.0f;
		res.m_reflector = new Reflector(res.m_transform, reflprot);
		res.m_reflector.owner = res;
		return res;
	}
}