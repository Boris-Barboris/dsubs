module dsubs_client.lib.soundio;

import std.algorithm;
import std.range;
import std.stdio;
import std.string;

import soundio.soundio;

import dsubs_client.common;


final class SoundIoException: Exception
{
	mixin ExceptionConstructors;
}

private void wrapErr(int err)
{
	if (err != 0)
		throw new SoundIoException(cast(string) soundio_strerror(err).fromStringz);
}

void loadAudioLib()
{
	sio = soundio_create();
	wrapErr(soundio_connect(sio));
	soundio_flush_events(sio);
	int deviceIdx = soundio_default_output_device_index(sio);
	if (deviceIdx < 0)
	{
		error("No audio devices found, disabling audio");
		s_noAudio = true;
		return;
	}
	s_device = soundio_get_output_device(sio, deviceIdx);
}

void unloadAudioLib()
{
	// TODO
}

private __gshared
{
	SoundIo* sio;
	SoundIoDevice* s_device;
	bool s_noAudio;
}


/// Sound source that can be appended to. At most one buffer is enqueued, new
/// buffers will cause rewind.
final class StreamingSoundSource
{
	this()
	{
		if (s_noAudio)
			return;
		m_ostream = soundio_outstream_create(s_device);
		m_ostream.format = SoundIoFormat.SoundIoFormatS16LE;
		m_ostream.sample_rate = 4096;
		m_ostream.layout = *soundio_channel_layout_get_builtin(
			SoundIoChannelLayoutId.SoundIoChannelLayoutIdMono);
		m_ostream.userdata = cast(void*) this;
		m_ostream.write_callback = &writeCallback;
		gain = 0.0f;
		wrapErr(soundio_outstream_open(m_ostream));
	}

	private
	{
		SoundIoOutStream* m_ostream;
		short[] m_curSamples;
		short[] m_nextSamples;
		int m_queuedCount;
	}

	@property int queuedCount() const { return m_queuedCount; }

	~this()
	{
		if (s_noAudio)
			return;
		soundio_outstream_destroy(m_ostream);
	}

	private extern(C) static void writeCallback(SoundIoOutStream* outstream,
		int frame_count_min, int frame_count_max)
	{
		StreamingSoundSource source = cast(StreamingSoundSource) outstream.userdata;
		SoundIoChannelArea* areas;
		int toWrite = frame_count_max;
		while (toWrite > 0 && source.m_curSamples.length > 0)
		{
			int frameCount = min(frame_count_max, source.m_curSamples.length);
			auto err = soundio_outstream_begin_write(source.m_ostream, &areas,
				&frameCount);
			if (err != 0)
			{
				error(soundio_strerror(err).fromStringz);
				assert(0);
			}
			for (int i = 0; i < frameCount; i++)
			{
				short* ptr = cast(short*) areas[0].ptr + areas[0].step * i;
				*ptr = source.m_curSamples[i];
			}
			err = soundio_outstream_end_write(source.m_ostream);
			if (err != 0)
			{
				error(soundio_strerror(err).fromStringz);
				assert(0);
			}
			source.m_curSamples = source.m_curSamples[frameCount .. $];
			if (source.m_curSamples.length == 0)
				source.swapBufs();
			toWrite -= frameCount;
		}
	}

	/// append sound to the source
	void append(short[] samples, int srate)
	{
		if (s_noAudio)
			return;
		trace("appending sound, ", samples.length, " samples, ", srate, " srate");
		assert(srate == 4096);
		synchronized(this)
		{
			if (m_queuedCount > 0)
				m_nextSamples = samples;
			else
			{
				m_curSamples = samples;
				m_queuedCount = 1;
			}
		}
		ensurePlaying();
	}

	private void swapBufs()
	{
		synchronized(this)
		{
			m_curSamples = m_nextSamples;
			m_nextSamples.length = 0;
			m_queuedCount--;
		}
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
	}

	@property float gain()
	{
		if (s_noAudio)
			return 1.0f;
		return 1.0f;
	}

	private void ensurePlaying()
	{
		wrapErr(soundio_outstream_start(m_ostream));
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