/*
DSubs
Copyright (C) 2017-2025 Baranin Alexander

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
module dsubs_server.animal;

import std.algorithm.comparison: max;

import dsubs_common.containers.array;
import dsubs_common.math;
import dsubs_common.api.entities: KinematicSnapshot;
import dsubs_common.json;

import dsubs_sound.common: uniform;
import dsubs_sound.soundsource;
import dsubs_sound.activesonar: Reflector, ReflectorPrototype;

import dsubs_server.common;
import dsubs_server.dynamics;
import dsubs_server.simulator;
import dsubs_server.acoustics;
import dsubs_server.observable;
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
	@property const(RigidBody) rigidBody() const { return m_rigidBody; }

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

	@property vec2d destination() const { return m_destination; }

	@property bool arrivedAtDestination()
	{
		return (transform.wposition - m_destination).length < 30.0f;
	}

	@property ref PrerecordedSoundConfig[] randomSounds()
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

	protected KinematicSnapshot fakeTransformSnapshot()
	{
		KinematicSnapshot res;
		res.atTime = simulator.worldTime;
		res.position = m_transform.wposition;
		res.rotation = m_transform.wrotation;
		res.velocity = m_rigidBody.kinet.vel;
		res.angVel = 0.0;
		return res;
	}

	override void updateObservableCache()
	{
		super.updateObservableCache();
		m_observableCache.transformSnapshot = fakeTransformSnapshot();
		m_observableCache.stateUpdateJson["name"] = m_name;
		m_observableCache.stateUpdateJson["species"] = species;
		m_observableCache.stateUpdateJson["speed"] = this.rigidBody.kinet.velLength;
		m_observableCache.stateUpdateJson["mass"] = this.rigidBody.mass;
		m_observableCache.stateUpdateJson["course"] =
			-this.rigidBody.kinet.rotation.compassAngle.rad2dgr;
		m_observableCache.stateUpdateJson["destination"] = destination.v.toJson;
	}
}


final class AnimalCollection: IObservableCollection
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

	mixin ObservableCollectionCommonMethods!(m_entities);
}


struct AnimalFactoryConfig
{
	PrerecordedSoundConfig[] randomSoundConfigs;
	JukeboxSoundTimings soundTimings;
	float maxSpeed = 0.0;
	ReflectorPrototype reflector;
	float mass;
	string species;
}


final class AnimalFactory
{
	AnimalFactoryConfig animalConfig;
	alias animalConfig this;

	final Animal build(string name)
	{
		Animal res = new Animal(cast() this);
		res.m_jukebox.randomSounds = animalConfig.randomSoundConfigs;
		res.m_jukebox.soundTimings = soundTimings;
		res.m_name = name;
		res.m_rigidBody.mass = mass;
		res.m_rigidBody.moi = 1.0f;
		res.m_reflector = new Reflector(res.m_transform, reflector);
		res.m_reflector.owner = res;
		return res;
	}
}