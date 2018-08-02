module dsubs_client.lib.openal;

import std.range;

import derelict.openal.al;

import dsubs_client.common;

void loadAudioLib()
{
	DerelictAL.load();
	s_device = alcOpenDevice(null);
	ALenum err;
	alcGetError(&err);
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

void unloadAudioLib()
{
	if (s_noAudio)
		return;
	alcCloseDevice(s_device);
}

private
{
	ALCdevice* s_device = null;
	ALCcontext* s_context = null;
	bool s_noAudio;
}

pragma(inline)
private void openalCheckErr(string msgStart)
{
	ALenum err;
	alcGetError(&err);
	enforce(err == AL_NO_ERROR, msgStart ~ err.to!string);
}

/// Sound source that can be appended to. At most one buffer is enqueued, new
/// buffers will cause rewind.
final class StreamingSoundSource
{
	this()
	{
		if (s_noAudio)
			return;
		alGenSources(1, &source);
		openalCheckErr("Unable to create audio source: ");
		alSourcef(source, AL_MAX_GAIN, 100.0f);
		openalCheckErr("Cannot set max gain: ");
		gain = 0.0f;
	}

	private
	{
		ALuint source;
		int m_queuedCount;
	}

	@property int queuedCount() const { return m_queuedCount; }

	~this()
	{
		if (s_noAudio)
			return;
		alSourceStop(source);
		ALenum err;
		alcGetError(&err);
		alDeleteSources(1, &source);
		alcGetError(&err);
		if (err != AL_NO_ERROR)
			error("error during source deletion: " ~ err.to!string);
	}

	/// append sound to the source
	void append(const short[] samples, int srate)
	{
		if (s_noAudio)
			return;
		trace("appending sound, ", samples.length, " samples, ", srate, " srate");
		ALuint newBuf;
		alGenBuffers(1, &newBuf);
		openalCheckErr("Cannot create new buffer: ");
		alBufferData(newBuf, AL_FORMAT_MONO16, samples.ptr,
			(samples.length * short.sizeof).to!int, srate);
		openalCheckErr("Unable to fill audio buffer with data: ");
		alSourceQueueBuffers(source, 1, &newBuf);
		openalCheckErr("Cannot enqueue buffer: ");
		m_queuedCount++;
		ensurePlaying();
	}

	@property void gain(float rhs)
	{
		if (s_noAudio)
			return;
		alSourcef(source, AL_GAIN, rhs);
		openalCheckErr("Cannot set gain: ");
	}

	@property float gain()
	{
		if (s_noAudio)
			return 1.0f;
		float res;
		alGetSourcef(source, AL_GAIN, &res);
		openalCheckErr("Cannot get gain: ");
		return res;
	}

	private void ensurePlaying()
	{
		ALint propVal;
		alGetSourcei(source, AL_SOURCE_STATE, &propVal);
		openalCheckErr("Cannot get source state: ");
		if (propVal != AL_PLAYING)
		{
			trace("audio source was not playing");
			alSourcePlay(source);
			openalCheckErr("Cannot play an audio source: ");
		}
	}

	void pullFinishedBuffers()
	{
		if (s_noAudio)
			return;
		ALuint oldBuf;
		ALint processed;
		alGetSourcei(source, AL_BUFFERS_PROCESSED, &processed);
		assert(processed <= m_queuedCount);
		while(processed > 0)
		{
			alSourceUnqueueBuffers(source, 1, &oldBuf);
			openalCheckErr("Unable to unqueue buffer: ");
			m_queuedCount--;
			assert(m_queuedCount >= 0);
			alDeleteBuffers(1, &oldBuf);
			openalCheckErr("Unable to delete unqueued buffer: ");
			processed--;
		}
	}
}