module dsubs_sound.activesonar;

import std.algorithm;

import dsubs_common.event;

import dsubs_sound.common;
import dsubs_sound.spectrum;
import dsubs_sound.soundsource;
import dsubs_sound.water;
import dsubs_sound.wav;
import dsubs_sound.reverb;



struct ReflectorPrototype
{
	vec2f size;
	vec3f reflectivity;
}


/// Rectangular reflector of active sonar impulses
final class Reflector
{
	this(Transform2D t, const ReflectorPrototype p)
	{
		m_transform = t;
		size = p.size;
		reflectivity = p.reflectivity;
	}

	private Transform2D m_transform;

	@property Transform2D transform() { return m_transform; }

	/// x - width, y - length
	private vec2f size;

	/// reflectivities of front (x), sides (y, axial symmetry assumed) and rear (z)
	private vec3f reflectivity;

	/// calculate cross-radius and effective reflectivity towards the emitter
	public void calcForEmitter(vec2d emitterPos, out float crad, out float reflect) const
	{
		float relBearing = courseAngle(emitterPos - m_transform.wposition) -
			m_transform.wrotation;
		float diffFromSide = (fabs(clampAnglePi(relBearing)) - PI_2) / PI_2;
		float absDiffFromSide = fabs(diffFromSide);
		crad = size.y * (1.0f - absDiffFromSide) + size.x * absDiffFromSide;
		if (diffFromSide >= 0.0f)
		{
			// emission from the rear
			reflect = reflectivity.y * (1.0f - absDiffFromSide) +
				reflectivity.z * absDiffFromSide;
		}
		else
		{
			// emission from the frontal semisphere
			reflect = reflectivity.y * (1.0f - absDiffFromSide) +
				reflectivity.x * absDiffFromSide;
		}
	}
}


struct Chirp
{
	int startFreq;
	int endFreq;
	float duration;		/// chirp duration in seconds
}

/// Parameters than uniquely identify reference time domain ping signal
struct PingParameters
{
	Chirp[] chirps;
	int tdsLength = 2;		/// tds length in seconds
	float effectiveFreq;	/// abstracted away "main" frequency.
}


/// Cache for reference Tds ping signals of unity amplitude
struct PingTdsCache
{
	private
	{
		TimeDomainSignal[immutable PingParameters*] m_cache;
	}

	void put(immutable PingParameters* params)
	{
		m_cache[params] = genPingSound(params.tdsLength, params.chirps);
	}

	immutable(TimeDomainSignal)* get(immutable PingParameters* params) immutable
	{
		return params in m_cache;
	}
}


struct ActiveSonarPrototype
{
	/// form of the ping chirp, wich will be used to synthesize time domain signal
	immutable(PingParameters)* pingParams;
	/// number of beams, formed by transducer
	int beamCount = 210;
	/// Sonar is capable of scanning sector of this size
	float span = 210.0f;
	/// rows in image per second
	int rowsPerSec = 10;
	/// max ping duration (seconds)
	int maxSec = 60;
	/// minimum ping power
	dB minIlevel = 60.0f;
	/// maximum ping power
	dB maxIlevel = 140.0f;
	dB baseNoise = 1.0f;
	/// position is more imprecise, the furthere away the target is
	float positionErrorK = 0.03f;
	/// visible size of target is larger than it should be with
	/// the distance (reflected signal is less concentrated)
	float sizeErrorK = 1e-4f;
	float flowNoiseMult = 0.001f;
}


final class ActiveSonar
{
	this(Transform2D trans, const ActiveSonarPrototype proto,
		immutable(PingTdsCache)* pingCache)
	{
		m_transform = trans;
		m_proto = proto;
		m_tds = pingCache.get(m_proto.pingParams);
	}

	private
	{
		Transform2D m_transform;
		const ActiveSonarPrototype m_proto;
		immutable(TimeDomainSignal)* m_tds;
		bool m_hasListener;
		SonarPing m_trackedPing;

		/// speed in knots at the start of integration
		float m_ktsStart = 0.0f;
		float m_ktsEnd = 0.0f;
	}

	/// invoked by simulator before kinematic update happens
	Event!(void delegate()) onPreSimulation;
	/// invoked by simulator right after kinematic update happens
	Event!(void delegate()) onPostSimulation;

	/// set speed at the start of integration
	@property float ktsStart(float rhs)
	{
		return m_ktsStart = rhs;
	}

	/// set speed at the end of integration
	@property float ktsEnd(float rhs)
	{
		return m_ktsEnd = rhs;
	}

	/// currently tracked ping. Null if none.
	@property SonarPing trackedPing() { return m_trackedPing; }

	@property bool hasListener() const { return m_hasListener; }

	@property void hasListener(bool rhs)
	{
		m_hasListener = rhs;
		if (!rhs)
			m_trackedPing = null;
	}
}


/// Immovable sonar ping source.
final class SonarPing: SoundSource
{
	this(vec2d position, immutable(PingParameters)* params, IntensityLevel power)
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
		const PingParameters* m_params;
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


private TyGverb* g_reverbator;

// make sure g_reverbator is build for this thread
private void ensureReverberatorBuilt()
{
	if (g_reverbator is null)
	{
		GverbParams params = GverbParams(4096, 50.0f, 50.0f, 2.0f,
			0.1f, 0.0f, 0.01f, 0.6f, 20.0f);
		g_reverbator = new TyGverb(params);
	}
}

private TimeDomainSignal genPingSound(int lifeTime, immutable Chirp[] chirps,
	int srate = 4096)
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
	float[] reverbed;
	ensureReverberatorBuilt();
	g_reverbator.set_revtime(lifeTime);
	g_reverbator.applyToBuf(res.samples, reverbed);
	g_reverbator.flush();
	res.samples = reverbed;
	return res;
}

unittest
{
	TimeDomainSignal tds = genPingSound(2, [Chirp(1100, 1300, 0.3f)]);
	writeWavFile("midfreq-chirp.wav", tds.samples, 0.6f, tds.samplingRate);
}