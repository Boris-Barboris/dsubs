module dsubs_server.acoustics;

import dsubs_sound.hydrophone;
import dsubs_sound.soundsource;
import dsubs_sound.spectrum;

import dsubs_server.common;


final class AcousticEnv
{
	private
	{
		Hydrophone[Hydrophone] m_hydrophones;
		SoundSource[SoundSource] m_sources;
	}

	void registerEntity(Hydrophone e)
	{
		synchronized(this)
		{
			m_hydrophones[e] = e;
		}
	}

	void registerEntity(SoundSource e)
	{
		synchronized(this)
		{
			m_sources[e] = e;
		}
	}

	void unregisterEntity(Hydrophone e)
	{
		synchronized(this)
		{
			m_hydrophones.remove(e);
		}
	}

	void unregisterEntity(SoundSource e)
	{
		synchronized(this)
		{
			m_sources.remove(e);
		}
	}


	/// perform physics update for all entities
	void applySourcesOnHydrophones()
	{
		foreach (hydrophone; Globals.taskPool.parallel(m_hydrophones.values, 2))
		{
			foreach (source; m_sources.byValue)
				hydrophone.applySound(source);
		}
	}
}