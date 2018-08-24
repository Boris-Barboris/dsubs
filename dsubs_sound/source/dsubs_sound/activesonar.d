module dsubs_sound.activesonar;

import std.algorithm;

import dsubs_common.event;

import dsubs_sound.common;
import dsubs_sound.spectrum;
import dsubs_sound.soundsource;
import dsubs_sound.water;
import dsubs_sound.wav;



/// Rectangular reflector of active sonar impulses
final class Reflector
{
	this(Transform2D t)
	{
		m_transform = t;
	}

	private Transform2D m_transform;

	final @property Transform2D transform() { return m_transform; }

	private vec2f m_size;
	private float m_area;

	@property vec2f size() const { return m_size; }

	@property void size(vec2f rhs)
	{
		m_size = rhs;
		m_area = m_size.x * m_size.y;
	}

	@property float area() const { return m_area; }

	// reflectivities of front, sides (axial symmetry assumed) and rear
	private vec3f m_reflect;
}


struct Chirp
{
	int startFreq;
	int endFreq;
	float duration;
}

struct PingParameters
{
	/// radial (range) resolution, meters
	float radRes = 50.0f;
	/// number of radial slices. Determines max range.
	int radCount = 10000 / 50;
	float lifeTime = 3.0f;
	Chirp[] chirps;
	float effectiveFreq;	/// abstracted away "main" frequency
	dB pingLevel;
	/// reference reflection intensity that corrensponds to full white color in the image
	dB refMaxLevel = 140.0f;
}


private TimeDomainSignal genPingSound(float lifeTime, const Chirp[] chirps, int srate = 4096)
{
	assert(srate > 0);
	assert(chirps.length > 0);
	float phase = uniform(-3.0f, 3.0f);
	float time = 0.0f;
	float dt = 1.0f / srate;
	TimeDomainSignal res;
	res.samplingRate = srate;
	res.samples.length = lrint(srate * lifeTime).to!size_t;
	int curChirp = 0;
	float freq = chirps[curChirp].startFreq;
	float chirpDur = chirps[curChirp].duration;
	float dfreq = (chirps[curChirp].endFreq - freq) / chirps[curChirp].duration * dt;
	for (size_t i = 0; i < res.samples.length; i++)
	{
		res.samples[i] = sin(phase);
		phase += freq * dt * 2 * PI;
		if (phase > 2 * PI)
			phase -= 2 * PI;
		freq += dfreq;
		time += dt;
		if (time > chirpDur)
		{
			time -= chirpDur;
			curChirp++;
			if (curChirp >= chirps.length)
			{
				res.samples[i+1..$] = 0.0f;
				break;
			}
			freq = chirps[curChirp].startFreq;
			dfreq = (chirps[curChirp].endFreq - freq) / chirps[curChirp].duration * dt;
		}
	}
	return res;
}

unittest
{
	TimeDomainSignal tds = genPingSound(3.0f, [Chirp(1100, 1300, 0.3f)]);
	writeWavFile("midfreq-chirp.wav", tds.samples, 0.7f, tds.samplingRate);
}


final class SonarPing: SoundSource
{
	this(vec2d position, PingParameters params)
	{
		m_position = position;
		m_params = params;
		savePrevPos();
	}

	private
	{
		// time passed since ping creation
		float m_timeSince = 0.0f;
		vec2d m_position;
		PingParameters m_params;
		TimeDomainSignal m_tds;
		ubyte[][] m_image;
	}

	override @property vec2d position() { return m_position; }

	override @property float radius() const { return 30.0f; }

	override void buildSignals(vec2d listenerPos,
		scope void delegate(float bandIntensity, TimeDomainSignal tds) onSignalReady,
		int minFreq, int maxFreq, bool needTds, float dissMod = 1.0f) const
	{

	}
}