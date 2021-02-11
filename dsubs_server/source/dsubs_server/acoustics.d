module dsubs_server.acoustics;

import std.algorithm.setops: cartesianProduct;

import dsubs_common.containers.array;

import dsubs_sound.activesonar;
import dsubs_sound.hydrophone;
import dsubs_sound.soundsource;
import dsubs_sound.spectrum;

import dsubs_server.common;


final class AcousticEnv
{
	private
	{
		Hydrophone[] m_hydrophones;
		SoundSource[] m_sources;
		ActiveSonar[] m_sonars;
		Reflector[] m_reflectors;
	}

	@property Reflector[] reflectors() { return m_reflectors; }

	@property SoundSource[] sources() { return m_sources; }

	// all register and unregister calls are supposed to
	// be called while holding simMut.reader

	void registerHydrophone(Hydrophone e)
	{
		synchronized(this)
		{
			m_hydrophones ~= e;
		}
	}

	void registerSource(SoundSource e)
	{
		synchronized(this)
		{
			m_sources ~= e;
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
			m_hydrophones.removeFirstUnstable(e);
		}
	}

	void unregisterSource(SoundSource e)
	{
		synchronized(this)
		{
			m_sources.removeFirstUnstable(e);
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

		foreach (Hydrophone hydrophone; Globals.taskPool.parallel(m_hydrophones, 1))
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
		foreach (Hydrophone hydrophone; Globals.taskPool.parallel(m_hydrophones, 1))
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
			SoundSource s = m_sources[i];
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
				m_sources[i] = m_sources[$-1];
				m_sources.length--;
			}
		}
	}
}