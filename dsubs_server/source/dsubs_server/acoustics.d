module dsubs_server.acoustics;

import dsubs_common.containers.array;

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
	}

	// all register and unregister calls are supposed to
	// be called while holding simMut

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

	void preSimulation()
	{
		foreach (source; Globals.taskPool.parallel(m_sources, 16))
			source.onPreSimulation();
		foreach (h; m_hydrophones)
			h.onPreSimulation();
	}

	void postSimulation(float dt)
	{
		foreach (source; Globals.taskPool.parallel(m_sources, 8))
			source.onPostSimulation(dt);
		foreach (h; m_hydrophones)
			h.onPostSimulation();
	}

	void applySourcesOnHydrophones()
	{
		foreach (Hydrophone hydrophone; Globals.taskPool.parallel(m_hydrophones, 1))
		{
			int workerIdx = Globals.taskPool.workerIndex.to!int;
			auto q = Globals.sctx.queue(workerIdx);
			if (!hydrophone.active)
				continue;
			hydrophone.resetAndStartIsotropic(q);
			foreach (source; m_sources)
				hydrophone.applySoundSource(q, source);
			if (hydrophone.listenDirValid)
				hydrophone.startFinalizePcbData(q, 100.0f);
		}

		foreach (Hydrophone hydrophone; Globals.taskPool.parallel(m_hydrophones, 1))
		{
			int workerIdx = Globals.taskPool.workerIndex.to!int;
			auto q = Globals.sctx.queue(workerIdx);
			if (!hydrophone.active)
				continue;
			hydrophone.flushSourceQueue();
			hydrophone.endIsotropic();
			if (hydrophone.listenDirValid)
				hydrophone.endFinalizePcbData();
		}
	}
}