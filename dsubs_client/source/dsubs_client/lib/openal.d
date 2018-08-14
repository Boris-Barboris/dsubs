module dsubs_client.lib.openal;

import std.algorithm;
import std.range;
import std.stdio;

import derelict.openal.al;
// library needs resampler=bsinc in config

import dsubs_client.common;

void loadAudioLib()
{
	DerelictAL.load();
	s_device = alcOpenDevice(null);
	ALenum err = alcGetError(s_device);
	if (s_device is null)
	{
		error("OpenAL unable to open audio device: ", err);
		s_noAudio = true;
		return;
	}
	s_context = alcCreateContext(s_device, null);
	openalcCheckErr("Unable to create audio context: ");
	alcMakeContextCurrent(s_context);
	openalcCheckErr("Unable to activate audio context: ");
	alDistanceModel(AL_NONE);
	openalcCheckErr("Unable to set distance model: ");
}

void unloadAudioLib()
{
	if (s_noAudio)
		return;
	alcCloseDevice(s_device);
}

private __gshared
{
	ALCdevice* s_device;
	ALCcontext* s_context;
	bool s_noAudio;
}

pragma(inline)
private void openalcCheckErr(string msgStart)
{
	ALenum err = alcGetError(s_device);
	enforce(err == AL_NO_ERROR, msgStart ~ err.to!string);
}

pragma(inline)
private void openalCheckErr(string msgStart)
{
	ALenum err = alGetError();
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
		alSourcef(source, AL_MAX_GAIN, 1.0f);
		openalCheckErr("Cannot set max gain: ");
		gain = 0.0f;
	}

	private
	{
		ALuint source;
		int m_queuedCount;

		enum float TARGET_MAX = short.max * 0.8f;
		enum float MAX_GAIN = 1e3;	// 40 dB
	}

	@property int queuedCount() const { return m_queuedCount; }

	~this()
	{
		if (s_noAudio)
			return;
		alSourceStop(source);
		ALenum err = alGetError();
		alDeleteSources(1, &source);
		err = alGetError();
		if (err != AL_NO_ERROR)
			error("error during source deletion: " ~ err.to!string);
	}

	/// append sound to the source
	void append(short[] samples, int srate)
	{
		if (s_noAudio)
			return;
		trace("appending sound, ", samples.length, " samples, ", srate, " srate");
		ALuint newBuf;
		alGenBuffers(1, &newBuf);
		openalCheckErr("Cannot create new buffer: ");
		// short smax = samples.map!(s => abs(s).to!short).maxElement();
		// float mgain = 1.0f;
		// if (gain != 0.0f)
		// 	mgain = min(MAX_GAIN, TARGET_MAX / smax);
		// foreach (ref s; samples)
		// 	s = lrint(float(s) * mgain).to!short;
		alBufferData(newBuf, AL_FORMAT_MONO16, samples.ptr,
			(samples.length * short.sizeof).to!int, srate);
		openalCheckErr("Unable to fill audio buffer with data: ");
		alSourceQueueBuffers(source, 1, &newBuf);
		openalCheckErr("Cannot enqueue buffer: ");
		m_queuedCount++;
		ensurePlaying();
	}

	void appendWav(string path)
	{
		if (s_noAudio)
			return;
		short[] samples;
		int srate, byteCount;
		loadWavFile(path, samples, byteCount, srate);
		append(samples, srate);
	}

	@property void gain(float rhs)
	{
		if (s_noAudio)
			return;
		enforce(rhs <= 1.0f && rhs >= 0.0f);
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


/// load mono
void loadWavFile(string filename, out short[] samples, out int byteCount, out int srate)
{
	File f = File(filename, "rb");
	f.seek(4 + 4 + 4 + 4 + 4 + 2 + 2);
	int[] srateArr = f.rawRead(new int[1]);
	enforce(srateArr.length == 1, "unexpected eof in wav file");
	srate = srateArr[0];
	f.seek(40);
	int[] byteLen = f.rawRead(new int[1]);
	enforce(byteLen.length == 1, "unexpected eof in wav file");
	byteCount = byteLen[0];
	enforce(byteCount % 2 == 0, "not 16-bit PCB?");
	int sampleCount = (byteCount / short.sizeof).to!int;
	f.seek(44);
	samples = f.rawRead(new short[sampleCount]);
}