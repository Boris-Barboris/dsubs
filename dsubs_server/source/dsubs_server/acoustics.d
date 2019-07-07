module dsubs_server.acoustics;

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
		SonarPing[] m_pings;
	}

	// all register and unregister calls are supposed to
	// be called while holding simMut.reader

	void registerHydrophone(Hydrophone e)
	{
		synchronized(this)
		{
			m_hydrophones ~= e;
		}
	}

	void registerPing(SonarPing e)
	{
		synchronized(this)
		{
			m_pings ~= e;
			m_sources ~= e;
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
		m_pings.length = 0;
		m_sources.length = 0;
	}

	void preSimulation()
	{
		foreach (source; Globals.taskPool.parallel(m_sources, 8))
			source.onPreSimulation();
		foreach (h; m_hydrophones)
			h.onPreSimulation();
		foreach (s; m_sonars)
			s.onPreSimulation();
	}

	void postSimulation(float dt)
	{
		foreach (source; Globals.taskPool.parallel(m_sources, 8))
			source.onPostSimulation(dt);
		foreach (h; m_hydrophones)
			h.onPostSimulation();
		foreach (s; m_sonars)
			s.onPostSimulation();
	}

	void processActiveSonars()
	{
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
					sonar.drawReflectors(q, m_reflectors);
				if (sonar.canGenerateSlice)
					sonar.startSliceGeneration(q);
			}
		}
	}

	void applySourcesOnHydrophones()
	{
		foreach (Hydrophone hydrophone; Globals.taskPool.parallel(m_hydrophones, 1))
		{
			if (!hydrophone.active)
				continue;
			int workerIdx = Globals.taskPool.workerIndex.to!int;
			auto q = Globals.sctx.queue(workerIdx);
			hydrophone.resetAndStartIsotropic(q);
			foreach (source; m_sources)
				hydrophone.applySoundSource(q, source);
			if (hydrophone.listenDirValid)
				hydrophone.startFinalizePcbData(q, 50.0f);
		}

		foreach (Hydrophone hydrophone; Globals.taskPool.parallel(m_hydrophones, 1))
		{
			if (!hydrophone.active)
				continue;
			hydrophone.flushSourceQueue();
			hydrophone.endIsotropic();
			if (hydrophone.listenDirValid)
				hydrophone.endFinalizePcbData();
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
			PrerecordedSoundSource ps = cast(PrerecordedSoundSource) s;
			if (ps is null)
			{
				i++;
				continue;
			}
			if (ps.samplesLeft == 0)
			{
				// source is no longer active and must be unregistered
				m_sources[i] = m_sources[$-1];
				m_sources.length--;
			}
			else
				i++;
		}

		i = 0;
		while (i < m_pings.length)
		{
			SonarPing p = m_pings[i];
			if (p.samplesLeft == 0)
			{
				// ping is no longer active and must be unregistered
				m_pings[i] = m_pings[$-1];
				m_pings.length--;
				m_sources.removeFirstUnstable(p);
			}
			else
				i++;
		}
	}
}