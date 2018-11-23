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

/// gains that conserve energy
private float[] getReverbGains(float[] relBinSizes, float zeroBin)
{
	assert(zeroBin > 0.0f);
	float[] res;
	res.length = 1 + relBinSizes.length;
	float totalRel = relBinSizes.sum();
	res[0] = 1.0f - zeroBin;
	for (int i = 0; i < relBinSizes.length; i++)
		res[i + 1] = relBinSizes[i] * zeroBin / totalRel;
	return res;
}

struct PingKernelParams
{
	dB peakIlevel;
	dB lowestIlevel;
	float dirPower;
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
	FloatImage reverbImg = FloatImage(ctx, fimg.w, fimg.h);

	PreparedReflector[] reflectors = [
		PreparedReflector(0.0f, 1000.0f, 75.0f, 40.0f, -2.0f),
		PreparedReflector(0.0f, 2000.0f, 75.0f, 40.0f, -2.0f),
		PreparedReflector(-1.0f, 3000.0f, 75.0f, 40.0f, -2.0f),
		PreparedReflector(-1.5f, 3000.0f, 75.0f, 40.0f, -2.0f),
		PreparedReflector(-2.0f, 3000.0f, 75.0f, 40.0f, -2.0f),
		PreparedReflector(-2.5f, 3000.0f, 75.0f, 40.0f, -2.0f),
		PreparedReflector(-3.0f, 3000.0f, 75.0f, 40.0f, -2.0f),
		PreparedReflector(0.0f, 5000.0f, 75.0f, 40.0f, -2.0f),
		PreparedReflector(0.0f, 7500.0f, 75.0f, 40.0f, -2.0f)
	];

	Buffer reflectBuf = Buffer(q, reflectors);
	enum float rangePerRow = 50.0f;

	PingKernelParams pparams = PingKernelParams(120.0f, 90.0f, 1.5f);

	Kernel k = q.mk_sonarReflectorPass;
	k.setArg(0, fimg.mem);
	k.setArg(1, ctx.b_wrdks.mem);
	k.setArg(2, pparams);	// pingParams
	k.setArg(3, 1400);		// pingFreq
	k.setArg(4, float(2 * PI));	// span
	k.setArg(5, rangePerRow);	// rangePerRow
	k.setArg(6, 4.0f);		// dissMod
	k.setArg(7, vec2f(0.03f, 0.03f));		// reflParamNoise
	k.setArg(8, reflectBuf.mem);
	k.setArg(9, reflectors.length.to!int);
	k.setArg(10, uintSeed());	// seed
	k.enqueue(q, 2, null, [fimg.w, fimg.h], null, null);

	auto start = MonoTime.currTime();
	q.finish();
	trace("mk_sonarReflectorPass took ", MonoTime.currTime() - start);

	const(float)[] reverbk = getReverbGains(
		[1.0f, 0.6f, 0.5f, 0.3f, 0.2f, 0.11f, 0.1, 0.06f, 0.04f, 0.01f], 0.1f);
	trace("reverbk: ", reverbk);
	Buffer reverbKbuf = Buffer(q, reverbk);

	k = q.mk_sonarReverbPass;
	k.setArg(0, fimg.mem);
	k.setArg(1, reverbImg.mem);
	k.setArg(2, reverbKbuf.mem);
	k.setArg(3, reverbk.length.to!int);
	k.setArg(4, 1.0f / 1500.0f);
	k.setArg(5, rangePerRow);
	k.enqueue(q, 2, null, [fimg.w, fimg.h], null, null);

	start = MonoTime.currTime();
	q.finish();
	trace("mk_sonarReverbPass took ", MonoTime.currTime() - start);

	k = q.mk_sonarIsotropicPass;
	k.setArg(0, reverbImg.mem);
	k.setArg(1, fimg.mem);
	k.setArg(2, ctx.b_wrdks.mem);
	k.setArg(3, pparams);	// pingParams
	k.setArg(4, 1400);		// pingFreq
	k.setArg(5, float(2 * PI));	// span
	k.setArg(6, 1.0f);		// baseNoise
	k.setArg(7, -20.0f);	// directivity
	k.setArg(8, -35.0f);	// waterReflectivity
	k.setArg(9, rangePerRow);		// rangePerRow
	k.setArg(10, 4.0f);		// dissMod
	k.setArg(11, uintSeed());	// seed
	k.enqueue(q, 2, null, [fimg.w, fimg.h], null, null);

	start = MonoTime.currTime();
	q.finish();
	trace("mk_sonarIsotropicPass took ", MonoTime.currTime() - start);

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

	ubyte[] resBytes = res.map!(s => (min(1.0f, max(0.0f, s / 50)) * ubyte.max).to!ubyte).array;
	write_image("active_sonar_" ~ maxRange ~ "km.png", fimg.w, fimg.h, resBytes, ColFmt.Y);

	// sonar slicing

	FloatImage slicedSonar = FloatImage(ctx, 200, fimg.h);

	k = q.mk_sonarSlicePass;
	k.setArg(0, fimg.mem);
	k.setArg(1, slicedSonar.mem);
	k.setArg(2, 0);	// yoffset
	k.setArg(3, float(dgr2rad(210)));	// destSpan
	k.setArg(4, 1.0f);		// rangePerRowRatio
	static assert (vec2f.sizeof == 2 * float.sizeof);
	k.setArg(5, vec2f(0.0f, -1.0f));	// relRotations
	k.setArg(6, vec2f(0.0f, 0.0f));		// angVels
	k.setArg(7, -75.0f);					// flowNoiseGain
	k.setArg(8, vec2f(0.0f, 20.0f));		// kts
	k.setArg(9, 1400);					// pingFreq
	k.setArg(10, 1.0f / 70.0f);		// endScale
	k.setArg(11, seaNoiseIL(1400).val - 25.0f);		// zeroLevel
	k.enqueue(q, 2, null, [slicedSonar.w, slicedSonar.h], null, null);

	res.length = slicedSonar.w * slicedSonar.h;
	slicedSonar.enqueueRead(q, res, [0, 0], [slicedSonar.w, slicedSonar.h]).waitFor();

	foreach (float r; res)
	{
		assert(!isNaN(r));
		assert(!isInfinity(r));
	}

	resBytes = res.map!(s => (min(1.0f, max(0.0f, s)) * ubyte.max).to!ubyte).array;
	write_image("active_sonar_" ~ maxRange ~ "km_sliced.png",
		slicedSonar.w, slicedSonar.h, resBytes, ColFmt.Y);
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