module dsubs_client.lib.openal;

import std.range;

import derelict.openal.al;

import dsubs_client.common;

void loadAudioLib()
{
	DerelictAL.load();
	s_device = alcOpenDevice(null);
	ALenum err = alcGetError();
	if (s_device is null)
	{
		error("OpenAL unable to open audio device: ", err);
		s_noAudio = true;
		return;
	}
	s_context = alcCreateContext(s_device, null);
	openalCheckErr("Unable to create audio context: ");
	alcMakeContextCurrent(s_context);
	openalCheckErr("Unable to activate audio context: ");
}

private
{
	ALCdevice* s_device = null;
	ALCcontext* s_context = null;
	bool s_noAudio;
}

private void openalCheckErr(string msgStart)
{
	ALenum err = alcGetError();
	enforce(err == AL_NONE, msgStart ~ err.to!string);
}

/// Sound source that can be appended to. At most one buffer is enqueued, new
/// buffers will cause rewind.
final class StreamingSoundSource
{
	this()
	{
		alGenSources(1, &source);
		openalCheckErr("Unable to create audio source: ");
	}

	private
	{
		ALuint* source;
	}

	void append(short[] samples, int srate)
	{
		pullFinishedBuffers();

	}

	private void pullFinishedBuffers()
	{
		ALuint* oldBuf;
		ALenum err = AL_NONE;
		do
		{
			alSourceUnqueueBuffers(source, 1, &oldBuf);
			err = alcGetError();
			if (err == AL_NONE)
			{
				alDeleteBuffers(1, oldBuf);
				openalCheckErr("Unable to delete unqueued buffer: ");
			}
		} while (err == AL_NONE);
	}
}