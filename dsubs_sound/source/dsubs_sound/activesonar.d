module dsubs_sound.activesonar;

import std.algorithm;

import dsubs_common.event;

import dsubs_sound.common;
import dsubs_sound.spectrum;
import dsubs_sound.soundsource;
import dsubs_sound.opencl;
import dsubs_sound.water;
import dsubs_sound.wav;
import dsubs_sound.reverb;



struct ReflectorPrototype
{
	vec2f size;
	dB[3] reflectivity;		/// negative to conserve energy
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
	private dB[3] reflectivity;

	/// calculate cross-radius and effective reflectivity towards the emitter
	// public void calcForEmitter(vec2d emitterPos, out float crad, out float reflect) const
	// {
	// 	float relBearing = courseAngle(emitterPos - m_transform.wposition) -
	// 		m_transform.wrotation;
	// 	float diffFromSide = (fabs(clampAnglePi(relBearing)) - PI_2) / PI_2;
	// 	float absDiffFromSide = fabs(diffFromSide);
	// 	crad = size.y * (1.0f - absDiffFromSide) + size.x * absDiffFromSide;
	// 	if (diffFromSide >= 0.0f)
	// 	{
	// 		// emission from the rear
	// 		reflect = reflectivity.y * (1.0f - absDiffFromSide) +
	// 			reflectivity.z * absDiffFromSide;
	// 	}
	// 	else
	// 	{
	// 		// emission from the frontal semisphere
	// 		reflect = reflectivity.y * (1.0f - absDiffFromSide) +
	// 			reflectivity.x * absDiffFromSide;
	// 	}
	// }
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
	int effectiveFreq;		/// abstracted away "main" frequency.
}


// /// Cache for reference Tds ping signals of unity amplitude
// struct PingTdsCache
// {
// 	private
// 	{
// 		Tds[immutable PingParameters*] m_cache;
// 	}

// 	void put(immutable PingParameters* params)
// 	{
// 		m_cache[params] = genPingSound(params.tdsLength, params.chirps);
// 	}

// 	Tds* get(immutable PingParameters* params) immutable
// 	{
// 		return params in m_cache;
// 	}
// }


struct ActiveSonarPrototype
{
	/// form of the ping chirp, wich will be used to synthesize time domain signal
	immutable(PingParameters)* pingParams;
	/// number of beams, formed by transducer
	int beamCount = 320;
	/// Sonar is capable of scanning sector of this size
	float span = 210.0f;
	/// rows in image per second
	int radialRes = 10;
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


private struct PreparedReflector
{
	float relBearing;
	float range;
	float width;
	float depth;
	dB reflectivity;
}

unittest
{
	import imageformats: write_image, ColFmt;
	import std.algorithm: map, maxElement;
	import std.array: array;
	import core.time: MonoTime;

	DsubsSoundOpenclCtx ctx = s_clCtx;
	CommandQueue q = ctx.queue(0);

	FloatImage fimg = FloatImage(ctx, 300, 200);

	PreparedReflector[] reflectors = [
		PreparedReflector(0.0f, 1000.0f, 75.0f, 40.0f, -2.0f),
		PreparedReflector(0.0f, 2000.0f, 75.0f, 40.0f, -2.0f),
		PreparedReflector(-1.0f, 3000.0f, 75.0f, 40.0f, -2.0f),
		PreparedReflector(0.0f, 5000.0f, 75.0f, 40.0f, -2.0f),
		PreparedReflector(0.0f, 7500.0f, 75.0f, 40.0f, -2.0f)
	];

	Buffer reflectBuf = Buffer(q, reflectors);
	enum float rangePerRow = 50.0f;

	Kernel k = q.mk_firstSonarPass;
	k.setArg(0, fimg.mem);
	k.setArg(1, ctx.b_wrdks.mem);
	k.setArg(2, 120.0f);	// pingIntens
	k.setArg(3, 2.0f);		// baseNoise
	k.setArg(4, 1400);		// pingFreq
	k.setArg(5, cast(float) dgr2rad(210.0f));	// span
	k.setArg(6, -20.0f);	// directivity
	k.setArg(7, -35.0f);	// waterReflectivity
	k.setArg(8, rangePerRow);		// rangePerRow
	k.setArg(9, 4.0f);		// dissMod
	k.setArg(10, 1.0f / 50);	// endScale
	k.setArg(11, uintSeed());	// seed
	k.setArg(12, reflectBuf.mem);
	k.setArg(13, reflectors.length.to!int);
	k.enqueue(q, 2, null, [fimg.w, fimg.h], null, null);

	auto start = MonoTime.currTime();
	q.finish();
	trace("mk_firstSonarPass took ", MonoTime.currTime() - start);

	float[] res;
	res.length = fimg.w * fimg.h;
	fimg.enqueueRead(q, res, [0, 0], [fimg.w, fimg.h]).waitFor();
	trace("active_sonar max intensity level = ", res.maxElement);

	foreach (float r; res)
	{
		assert(!isNaN(r));
		assert(!isInfinity(r));
	}

	string maxRange = (rangePerRow * fimg.h / 1000).to!int.to!string;

	ubyte[] resBytes = res.map!(s => (min(1.0f, s) * ubyte.max).to!ubyte).array;
	write_image("active_sonar_" ~ maxRange ~ "km.png", fimg.w, fimg.h, resBytes, ColFmt.Y);
}


// final class ActiveSonar
// {
// 	this(Transform2D trans, const ActiveSonarPrototype proto,
// 		immutable(PingTdsCache)* pingCache)
// 	{
// 		m_transform = trans;
// 		m_proto = proto;
// 		m_tds = pingCache.get(m_proto.pingParams);
// 	}

// 	private
// 	{
// 		Transform2D m_transform;
// 		const ActiveSonarPrototype m_proto;
// 		immutable(TimeDomainSignal)* m_tds;
// 		bool m_hasListener;
// 		SonarPing m_trackedPing;

// 		/// speed in knots at the start of integration
// 		float m_ktsStart = 0.0f;
// 		float m_ktsEnd = 0.0f;
// 	}

// 	/// invoked by simulator before kinematic update happens
// 	Event!(void delegate()) onPreSimulation;
// 	/// invoked by simulator right after kinematic update happens
// 	Event!(void delegate()) onPostSimulation;

// 	/// set speed at the start of integration
// 	@property float ktsStart(float rhs)
// 	{
// 		return m_ktsStart = rhs;
// 	}

// 	/// set speed at the end of integration
// 	@property float ktsEnd(float rhs)
// 	{
// 		return m_ktsEnd = rhs;
// 	}

// 	/// currently tracked ping. Null if none.
// 	@property SonarPing trackedPing() { return m_trackedPing; }

// 	@property bool hasListener() const { return m_hasListener; }

// 	@property void hasListener(bool rhs)
// 	{
// 		m_hasListener = rhs;
// 		if (!rhs)
// 			m_trackedPing = null;
// 	}
// }


// /// Immovable sonar ping source.
// final class SonarPing: SoundSource
// {
// 	this(vec2d position, immutable(PingParameters)* params, IntensityLevel power)
// 	{
// 		m_position = position;
// 		m_params = params;
// 		savePrevPos();
// 	}

// 	private
// 	{
// 		// time passed since ping creation
// 		float m_timeSince = 0.0f;
// 		vec2d m_position;
// 		const PingParameters* m_params;
// 		TimeDomainSignal m_tds;
// 		ubyte[][] m_image;
// 	}

// 	override @property vec2d position() { return m_position; }

// 	override @property float radius() const { return 30.0f; }

// 	override void buildSignals(vec2d listenerPos,
// 		scope void delegate(float bandIntensity, TimeDomainSignal tds) onSignalReady,
// 		int minFreq, int maxFreq, bool needTds, float dissMod = 1.0f) const
// 	{

// 	}
// }


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

private float[] genPingSound(int lifeTime, immutable Chirp[] chirps,
	int srate = GLOBAL_SRATE)
{
	assert(srate > 0);
	assert(chirps.length > 0);
	float phase = uniform(-3.0f, 3.0f);
	float time = 0.0f;
	float dt = 1.0f / srate;
	float[] samples;
	samples.length = lrint(srate * lifeTime).to!size_t;
	int curChirp = 0;
	float freq = chirps[curChirp].startFreq;
	float chirpDur = chirps[curChirp].duration;
	float dfreq = (chirps[curChirp].endFreq - freq) / chirps[curChirp].duration * dt;
	for (size_t i = 0; i < samples.length; i++)
	{
		samples[i] = sin(phase);
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
				samples[i+1..$] = 0.0f;
				break;
			}
			freq = chirps[curChirp].startFreq;
			dfreq = (chirps[curChirp].endFreq - freq) / chirps[curChirp].duration * dt;
		}
	}
	float[] reverbed;
	ensureReverberatorBuilt();
	g_reverbator.set_revtime(lifeTime);
	g_reverbator.applyToBuf(samples, reverbed);
	g_reverbator.flush();
	samples = reverbed;
	return samples;
}

unittest
{
	float[] samples = genPingSound(2, [Chirp(1100, 1300, 0.3f)]);
	writeWavFile("midfreq-chirp.wav", samples, 0.6f, GLOBAL_SRATE);
}