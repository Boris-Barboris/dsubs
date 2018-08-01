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

	void preUpdateSources()
	{
		foreach (source; Globals.taskPool.parallel(m_sources, 8))
			source.onPreSimulation();
	}

	void postUpdateSources(float dt)
	{
		foreach (source; Globals.taskPool.parallel(m_sources, 8))
		{
			source.onPostSimulation(dt);
			source.transform.ensureNotDirty();
		}
	}

	/// perform physics update for all entities
	void applySourcesOnHydrophones()
	{
		foreach (hydrophone; Globals.taskPool.parallel(m_hydrophones, 1))
		{
			hydrophone.onPreApply();
			foreach (source; m_sources)
				hydrophone.applySoundSource(source);
		}
	}
}