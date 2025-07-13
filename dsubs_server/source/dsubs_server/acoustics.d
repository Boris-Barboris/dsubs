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
module dsubs_server.acoustics;

import std.algorithm.setops: cartesianProduct;
import std.uuid;

import dsubs_common.containers.array;
import dsubs_common.json: toJson;

import dsubs_sound.activesonar;
import dsubs_sound.common: GLOBAL_SRATE, dB;
import dsubs_sound.hydrophone;
import dsubs_sound.soundsource;
import dsubs_sound.spectrum;
import dsubs_sound.image: loadSpectrumFromImageAndWarp;
import dsubs_sound.opencl: CommandQueue, DsubsSoundOpenclCtx;

import dsubs_server.common;
import dsubs_server.simulator;
import dsubs_server.observable;
import dsubs_server.propulsion;


final class AcousticEnv: IObservableCollection
{
	private
	{
		ObservableHydrophone[] m_hydrophones;
		ObservableSoundSource[] m_sources;
		ActiveSonar[] m_sonars;
		Reflector[] m_reflectors;
	}

	@property Reflector[] reflectors() { return m_reflectors; }

	@property auto sources() { return m_sources.map!(oss => oss.m_soundSource); }

	// all register and unregister calls are supposed to
	// be called while holding simMut.reader

	void registerHydrophone(Hydrophone e)
	{
		synchronized(this)
		{
			m_hydrophones ~= new ObservableHydrophone(e);
		}
	}

	void registerSource(SoundSource e)
	{
		synchronized(this)
		{
			m_sources ~= new ObservableSoundSource(e);
		}
	}

	void registerSonar(ActiveSonar e)
	{
		synchronized(this)
		{
			m_sonars ~= e;
		}
	}

	void registerReflector(Reflector e)
	{
		synchronized(this)
		{
			m_reflectors ~= e;
		}
	}

	void unregisterHydrophone(Hydrophone e)
	{
		synchronized(this)
		{
			m_hydrophones.removeFirst!(el => el.m_hydrophone is e)();
		}
	}

	void unregisterSource(SoundSource e)
	{
		synchronized(this)
		{
			m_sources.removeFirst!(el => el.m_soundSource is e)();
		}
	}

	void unregisterSonar(ActiveSonar e)
	{
		synchronized(this)
		{
			m_sonars.removeFirstUnstable(e);
		}
	}

	void unregisterReflector(Reflector e)
	{
		synchronized(this)
		{
			m_reflectors.removeFirstUnstable(e);
		}
	}

	/// release all releasable elements and clear the container
	void clean()
	{
		foreach (h; m_hydrophones)
			h.release();
		m_hydrophones.length = 0;
		foreach (s; m_sonars)
			s.release();
		m_sonars.length = 0;
		m_reflectors.length = 0;
		foreach (s; m_sources)
			s.release();
		m_sources.length = 0;
	}

	void preKinematics()
	{
		foreach (source; Globals.taskPool.parallel(m_sources, 8))
			source.onPreKinematics();
		foreach (h; m_hydrophones)
			h.onPreKinematics();
		foreach (s; m_sonars)
			s.onPreKinematics();
	}

	void postKinematics(float dt)
	{
		foreach (source; Globals.taskPool.parallel(m_sources, 8))
			source.onPostKinematics(dt);
		foreach (h; m_hydrophones)
			h.onPostKinematics();
		foreach (s; m_sonars)
			s.onPostKinematics();
	}

	void processActiveSonars()
	{
		foreach (Reflector r; m_reflectors)
			r.refreshTransform();

		foreach (ActiveSonar sonar; Globals.taskPool.parallel(m_sonars, 1))
		{
			if (!sonar.active)
			{
				if (sonar.canGenerateSlice)
					sonar.skipSiceGeneration();
			}
			else
			{
				int workerIdx = Globals.taskPool.workerIndex.to!int;
				auto q = Globals.sctx.queue(workerIdx);
				if (sonar.pingJustStarted)
					sonar.drawReflectors(q, m_reflectors.filter!(
						r => filterBySonarFilter(sonar, r)));
				if (sonar.canGenerateSlice)
					sonar.startSliceGeneration(q);
			}
		}
	}

	static bool filterBySonarFilter(ActiveSonar sonar, Reflector reflector)
	{
		if (sonar.reflectorFilter)
			return sonar.reflectorFilter(reflector);
		return true;
	}

	static bool filterByHydrophoneFilter(TupleT)(TupleT tuple)
	{
		if (tuple[0].soundSourceFilter)
			return tuple[0].soundSourceFilter(tuple[1]);
		return true;
	}

	void applySourcesOnHydrophones()
	{
		// Transform objects are lazily-rebuilt and in order to be race-free
		// we need to rebuild them eagerly before we fork to the taskpool.
		foreach (source; m_sources)
			source.transform.rebuild();

		foreach (ObservableHydrophone hydrophone; Globals.taskPool.parallel(
			m_hydrophones, 1))
		{
			if (hydrophone.active)
			{
				size_t workerIdx = Globals.taskPool.workerIndex;
				hydrophone.transform.rebuild();
				auto q = Globals.sctx.queue(workerIdx);
				hydrophone.resetAndStartIsotropic(q);
			}
		}

		// all possible pairs of (hydrophone, soundSource) where
		// hydrophone is interested in the source (can be uninterested when AI applies
		// a filter (major optimization)).
		auto hydrophoneSourceRange = cartesianProduct(
			m_hydrophones.filter!(h => h.active),
			m_sources
		).filter!(tuple => filterByHydrophoneFilter(tuple));

		foreach (hpSourceTuple; Globals.taskPool.parallel(hydrophoneSourceRange, 1))
		{
			size_t workerIdx = Globals.taskPool.workerIndex;
			auto q = Globals.sctx.queue(workerIdx);
			// applySoundSource can use any command queue, not bound
			// to a hydrophone in any way.
			hpSourceTuple[0].applySoundSource(q, hpSourceTuple[1]);
		}

		// at this point all source rendering commands are dispatched and it's
		// time to compose the final images on hydrophones. These functions require
		// that the composition is performed by 1 command queue per-hydrophone.
		foreach (ObservableHydrophone hydrophone; Globals.taskPool.parallel(
			m_hydrophones, 1))
		{
			if (hydrophone.active)
			{
				size_t workerIdx = Globals.taskPool.workerIndex;
				auto q = Globals.sctx.queue(workerIdx);
				hydrophone.endIsotropic();
				hydrophone.flushSourceQueue(q);
				hydrophone.adjustImprintsToOmni();
				if (hydrophone.listenDirValid)
					hydrophone.startFinalizePcbData(q);
			}
		}
		/// wait for completion of all OpenCL operations
		for (size_t i = 0; i < Globals.sctx.queueCount; i++)
			Globals.sctx.queue(i).finish();
	}

	void postAcousticsUpdate()
	{
		size_t i = 0;
		while (i < m_sources.length)
		{
			SoundSource s = m_sources[i].m_soundSource;
			s.onPostAcoustics();
			FiniteSoundSource finiteSource = cast(FiniteSoundSource) s;
			if (finiteSource is null || !finiteSource.finished)
			{
				i++;
				continue;
			}
			else
			{
				// source is no longer active and must be unregistered
				m_sources[i] = m_sources[$-1];	// unstable remove
				m_sources.length--;
				s.release();
			}
		}
	}

	// observation stuff
	void markNewObservationEpoch()
	{
		foreach (h; m_hydrophones)
			h.markNewObservationEpoch();
		foreach (ss; m_sources)
			ss.markNewObservationEpoch();
	}

	size_t appendObserverEntityUpdates(ref ObservableEntityUpdate[] appendTo)
	{
		foreach (h; m_hydrophones)
			appendTo ~= h.getObserverUpdate().toUnstructured();
		foreach (ss; m_sources)
			appendTo ~= ss.getObserverUpdate().toUnstructured();
		return m_hydrophones.length;
	}

	size_t appendObserverLogRecords(ref SimulatorLogRecord[] appendTo)
	{
		size_t res;
		foreach (h; m_hydrophones)
			res += h.appendObserverLogRecords(appendTo);
		foreach (ss; m_sources)
			res += ss.appendObserverLogRecords(appendTo);
		return res;
	}
}


private final class ObservableHydrophone: IObservableEntity
{
	private
	{
		UUID m_id;
		Hydrophone m_hydrophone;
		ObservableEntityCache m_observableCache;
	}

	@property Hydrophone hydrophone() { return m_hydrophone; }
	@property UUID id() { return m_id; }

	this(Hydrophone h)
	{
		m_id = randomUUID();
		m_hydrophone = h;
	}

	alias m_hydrophone this;

	void markNewObservationEpoch()
	{
		m_observableCache.clearCache();
	}

	StructuredObservableEntityUpdate getObserverUpdate()
	{
		if (m_observableCache.generated)
			return m_observableCache.entityUpdateCache;
		updateObservableCache();
		m_observableCache.generated = true;
		return m_observableCache.entityUpdateCache;
	}

	void updateObservableCache()
	{
		m_observableCache.id = m_id.toString();
		m_observableCache.entityType = m_hydrophone.classBaseName;
		m_observableCache.transformSnapshot.position = m_hydrophone.transform.wposition;
		m_observableCache.transformSnapshot.rotation = m_hydrophone.transform.wrotation;
		m_observableCache.transformSnapshot.velocity = vec2d(0, 0);
		m_observableCache.transformSnapshot.angVel = 0.0;
		m_observableCache.stateUpdateJson["active"] = m_hydrophone.active;
		m_observableCache.stateUpdateJson["mirrored"] = m_hydrophone.mirrored;
		m_observableCache.stateUpdateJson["canBeActive"] = m_hydrophone.canBeActive;
		m_observableCache.stateUpdateJson["maintainImprints"] =
			m_hydrophone.maintainImprints;
		m_observableCache.stateUpdateJson["listenDir"] = m_hydrophone.listenDir;
	}

	size_t appendObserverLogRecords(ref SimulatorLogRecord[] appendTo)
	{
		appendTo ~= m_observableCache.logRecords;
		return m_observableCache.logRecords.length;
	}
}


private final class ObservableSoundSource: IObservableEntity
{
	private
	{
		UUID m_id;
		SoundSource m_soundSource;
		ObservableEntityCache m_observableCache;
	}

	@property SoundSource soundSource() { return m_soundSource; }
	@property UUID id() { return m_id; }

	this(SoundSource ss)
	{
		m_id = randomUUID();
		m_soundSource = ss;
	}

	alias m_soundSource this;

	void markNewObservationEpoch()
	{
		m_observableCache.clearCache();
	}

	StructuredObservableEntityUpdate getObserverUpdate()
	{
		if (m_observableCache.generated)
			return m_observableCache.entityUpdateCache;
		updateObservableCache();
		m_observableCache.generated = true;
		return m_observableCache.entityUpdateCache;
	}

	void updateObservableCache()
	{
		m_observableCache.id = m_id.toString();
		m_observableCache.entityType = m_soundSource.classBaseName;
		m_observableCache.transformSnapshot.position = m_soundSource.transform.wposition;
		m_observableCache.transformSnapshot.rotation = m_soundSource.transform.wrotation;
		m_observableCache.transformSnapshot.velocity = vec2d(0, 0);
		m_observableCache.transformSnapshot.angVel = 0.0;
		if (m_soundSource.owner)
			m_observableCache.stateUpdateJson["owner"] = m_soundSource.owner.toString();
		if (m_soundSource.factory)
		{
			PropulsorFactory pf = cast(PropulsorFactory) m_soundSource.factory;
			if (pf)
			{
				m_observableCache.stateUpdateJson["propulsorConfig"] =
					pf.propulsorConfig.toJson();
			}

			PrerecordedSoundConfig psc = cast(PrerecordedSoundConfig) m_soundSource.factory;
			if (psc)
			{
				m_observableCache.stateUpdateJson["prerecordedSoundConfig"] =
					psc.toJson();
			}
		}
		m_observableCache.stateUpdateJson["radius"] = m_soundSource.radius;
	}

	size_t appendObserverLogRecords(ref SimulatorLogRecord[] appendTo)
	{
		appendTo ~= m_observableCache.logRecords;
		return m_observableCache.logRecords.length;
	}
}


// Serializable
final class PrerecordedSoundConfig: PrerecordedSoundPrototype
{
	string tdsFilename;

	this() {}

	this(string fileName, float radius, dB addToIlevel, float minOmniFactor = 0.0f)
	{
		tdsFilename = fileName;
		this.radius = radius;
		this.addToIlevel = addToIlevel;
		this.minOmniFactor = minOmniFactor;
	}

	override void incRef()
	{
		// trace("PrerecordedSoundConfig incRef: ", tdsFilename);
		// increases refcount
		auto varTdsPtr = Globals.sctx.getWavFile(tdsFilename, true);
		if (m_tds is null)
			m_tds = varTdsPtr;
	}

	override VarTds* tds()
	{
		if (m_tds && m_tds.released)
		{
			// m_tds was released through another PrerecordedSoundConfig referencing
			// the same tdsFilename
			m_tds = Globals.sctx.getWavFile(tdsFilename, false);
		}
		return m_tds;
	}

	override void decRef()
	{
		if (tdsFilename && m_tds)
		{
			assert(!m_tds.released);
			// trace("PrerecordedSoundConfig decRef: ", tdsFilename);
			Globals.sctx.releaseWavFileReference(tdsFilename, m_tds);
		}
	}

	override int getRefCount()
	{
		int res = Globals.sctx.getWavFileRefCount(tdsFilename);
		// trace("tdsFilename ", tdsFilename, " refCount is ", res);
		return res;
	}
}


struct SpectrumImageConfig
{
	string spectrumFilename;
	float noise = 0.0f;
	float bottomLevel = 80.0f;
	float topLevel = 160.0f;

	ISpectrum* loadSpectrum(CommandQueue q)
	{
		trace("Loading spectrum image ", spectrumFilename);
		return loadSpectrumFromImageAndWarp(
			q, spectrumFilename, noise, bottomLevel, topLevel
		);
	}
}


struct JukeboxSoundTimings
{
	/// average pause between songs
	usecs_t meanSongPause;
	usecs_t songPauseVariance;
	// if randomSounds are short and you want to compose
	// a song from repeating the sounds, this is how many times
	// the animal should repeat it.
	int songMinLength = 1;
	int songMaxLength = 1;
	// pause between sounds inside one song.
	usecs_t intrasongPause;
}


/// Set of prerecorded sounds that plays itself with specified periodicity
class Jukebox
{
	PrerecordedSoundConfig[] randomSounds;
	JukeboxSoundTimings soundTimings;

	private
	{
		Simulator m_simulator;
		Object m_owner;
		Transform2D m_transform;
	}

	protected
	{
		PrerecordedSoundSource m_currentSoundSource;
		int m_songCounter;
		int m_currentSongLength;
		usecs_t m_nextSoundStart;
	}

	this(Object owner, Transform2D transform)
	{
		m_owner = owner;
		m_transform = transform;
	}

	protected usecs_t generateNextSoundStart()
	{
		usecs_t lowBound, highBound;
		if (m_songCounter == 0)
		{
			m_currentSongLength = uniform!"[]"(
				soundTimings.songMinLength, soundTimings.songMaxLength);
			lowBound = soundTimings.meanSongPause -
				soundTimings.songPauseVariance;
			highBound = soundTimings.meanSongPause +
				soundTimings.songPauseVariance;
		}
		else
		{
			lowBound = soundTimings.intrasongPause;
			highBound = soundTimings.intrasongPause;
		}
		m_songCounter++;
		if (m_songCounter >= m_currentSongLength)
			m_songCounter = 0;
		return m_simulator.worldTime + max(0, uniform!"[]"(lowBound, highBound));
	}

	void setSimulator(Simulator sim)
	{
		m_simulator = sim;
	}

	void initNextSoundStart()
	{
		m_nextSoundStart = generateNextSoundStart();
	}

	void onSimUpdate()
	{
		if (m_simulator.worldTime >= m_nextSoundStart)
		{
			// spawn new sound source
			size_t sourceIdx = uniform!"[)"(0, randomSounds.length);
			// info("starting song");
			PrerecordedSoundPrototype proto = randomSounds[sourceIdx];
			m_currentSoundSource = new PrerecordedSoundSource(m_transform, proto);
			m_currentSoundSource.owner = m_owner;
			m_currentSoundSource.factory = proto;
			m_simulator.acous.registerSource(m_currentSoundSource);
			m_nextSoundStart =
				(1e6 * m_currentSoundSource.totalSamples / GLOBAL_SRATE).to!usecs_t +
				generateNextSoundStart();
		}
	}

	void shutdown()
	{
		if (m_currentSoundSource && !m_currentSoundSource.finished)
		{
			m_simulator.acous.unregisterSource(m_currentSoundSource);
			m_currentSoundSource.release();
		}
	}
}