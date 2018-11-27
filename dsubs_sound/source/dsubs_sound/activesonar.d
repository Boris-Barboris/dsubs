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
	vec2f size;				/// x - width, y - length
	dB[3] reflectivity;		/// negative to conserve energy
}

private struct PreparedReflector
{
	float relBearing;
	float range;
	float width;
	float depth;
	dB reflectivity;
}


/// Rectangular reflector of active sonar impulses
final class Reflector
{
	this(Transform2D t, const ReflectorPrototype p)
	{
		m_transform = t;
		m_proto = p;
	}

	private Transform2D m_transform;

	@property Transform2D transform() { return m_transform; }

	private ReflectorPrototype m_proto;

	/// calculate width, depth and reflectivity fields of PreparedReflector
	public void calcForEmitter(vec2d emitterPos, ref PreparedReflector res) const
	{
		float relBearing = courseAngle(emitterPos - m_transform.wposition) -
			m_transform.wrotation;
		float diffFromSide = (fabs(clampAnglePi(relBearing)) - PI_2) / PI_2;
		float absDiffFromSide = fabs(diffFromSide);
		res.width = m_proto.size.y * (1.0f - absDiffFromSide) +
			m_proto.size.x * absDiffFromSide;
		res.depth = m_proto.size.x * (1.0f - absDiffFromSide) +
			m_proto.size.y * absDiffFromSide;
		if (diffFromSide >= 0.0f)
		{
			// emission from the rear
			res.reflectivity = m_proto.reflectivity[1] * (1.0f - absDiffFromSide) +
				m_proto.reflectivity[2] * absDiffFromSide;
		}
		else
		{
			// emission from the frontal semisphere
			res.reflectivity = m_proto.reflectivity[1] * (1.0f - absDiffFromSide) +
				m_proto.reflectivity[0] * absDiffFromSide;
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
	int effectiveFreq;		/// abstracted away "main" frequency.
}


/// Cache for reference Tds ping signals of unity amplitude
// package struct PingTdsCache
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


/// reverb gains that conserve energy
private float[] getReverbGains(float[] relBinSizes, float zeroBin)
{
	assert(zeroBin >= 0.0f);
	float[] res;
	res.length = 1 + relBinSizes.length;
	float totalRel = relBinSizes.sum();
	assert(totalRel > 0.0f);
	res[0] = 1.0f - zeroBin;
	for (int i = 0; i < relBinSizes.length; i++)
		res[i + 1] = relBinSizes[i] * zeroBin / totalRel;
	return res;
}

struct PingKernelParams
{
	dB peakIlevel;		/// at the cental axis
	dB lowestIlevel;	/// opposite direction
	float dirPower;		/// power exponent of cosine directivity formula
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
		PreparedReflector(0.0f, 1000.0f, 75.0f, 20.0f, -2.0f),
		PreparedReflector(0.0f, 2000.0f, 75.0f, 20.0f, -2.0f),
		PreparedReflector(-1.0f, 3000.0f, 75.0f, 20.0f, -2.0f),
		PreparedReflector(-1.5f, 3000.0f, 75.0f, 20.0f, -2.0f),
		PreparedReflector(-2.0f, 3000.0f, 75.0f, 20.0f, -2.0f),
		PreparedReflector(-2.5f, 3000.0f, 75.0f, 20.0f, -2.0f),
		PreparedReflector(-3.0f, 3000.0f, 75.0f, 20.0f, -2.0f),
		PreparedReflector(0.0f, 5000.0f, 75.0f, 20.0f, -2.0f),
		PreparedReflector(0.0f, 7500.0f, 75.0f, 20.0f, -2.0f)
	];

	Buffer reflectBuf = Buffer(q, reflectors);
	enum float rangePerRow = 50.0f;

	PingKernelParams pparams = PingKernelParams(120.0f, 90.0f, 2.0f);

	Kernel k = q.mk_sonarReflectorPass;
	k.setArg(0, fimg.mem);
	k.setArg(1, ctx.b_wrdks.mem);
	k.setArg(2, pparams);	// pingParams
	k.setArg(3, 1200);		// pingFreq
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
	k.setArg(4, 1.0f / 2000.0f);
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
	k.setArg(4, 1200);		// pingFreq
	k.setArg(5, float(2 * PI));	// span
	k.setArg(6, -20.0f);	// directivity
	k.setArg(7, 5e-5f);	// waterReflectivity
	k.setArg(8, rangePerRow);		// rangePerRow
	k.setArg(9, 4.0f);		// dissMod
	k.setArg(10, vec2i(50, 20));		// perlCellSize
	k.setArg(11, vec2f(6.0f, 3.0f));	// perlNoiseGain
	k.setArg(12, uintSeed());	// seed
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
	k.setArg(9, 1200);					// pingFreq
	k.setArg(10, 1.0f / 50.0f);		// endScale
	k.setArg(11, seaNoiseIL(1200).val - 12.0f);		// zeroLevel
	k.setArg(12, 2.0f);			// baseNoise
	k.setArg(13, uintSeed());	// seed
	k.enqueue(q, 2, null, [slicedSonar.w, slicedSonar.h], null, null);

	res.length = slicedSonar.w * slicedSonar.h;
	slicedSonar.enqueueRead(q, res, [0, 0], [slicedSonar.w, slicedSonar.h]).waitFor();

	foreach (float r; res)
	{
		assert(!isNaN(r));
		assert(!isInfinity(r));
	}

	resBytes = res.map!(s => (min(1.0f, max(0.0f, s)) * ubyte.max).
		to!ubyte).array;
	write_image("active_sonar_" ~ maxRange ~ "km_sliced.png",
		slicedSonar.w, slicedSonar.h, resBytes, ColFmt.Y);
}

immutable PingParameters g_stdPingParams = immutable PingParameters(
		[Chirp(1100, 1300, 0.3f)], 2, 1200);


struct ActiveSonarPrototype
{
	/// form of the ping chirp, wich will be used to synthesize time domain signal
	immutable(PingParameters)* pingParams = &g_stdPingParams;
	/// number of beams in omnidirectional image
	int omniBeamCount = 320;
	/// Sonar is capable of scanning sector of this size (degrees)
	float span = 210.0f;
	/// rows in slice image per second
	int radialRes = 20;
	/// max ping duration (seconds)
	int maxSec = 15;
	/// max ping band intensity level
	dB maxPeakIlevel = 120.0f;
	dB minPeakIlevel = 90.0f;
	/// ping in the opposite direction is this different
	dB antiPeakIlevelDiff = -30.0f;
	/// power exponent of cosine directivity formula
	float pingDirPower = 2.0f;
	/// base uniform picture noise
	dB baseNoise = 2.0f;
	/// antennae directivity gain
	dB directivity = -20.0f;
	/// water mass reflectivity
	float waterReflectivity = 5e-5f;
	/// main sound dissipation modifier
	float dissMod = 4.0f;
	/// gain for flow noise
	dB flowNoiseGain = -69.0f;
	/// reflector bearing and range is randomized around true value by this ratio
	float reflBearingNoise = 0.02f;
	float reflRangeNoise = 0.02f;
	/// reverb gains gotten from getReverbGains function
	immutable(float)[] reverbk = getReverbGains(
		[1.0f, 0.5f, 0.2f, 0.1f, 0.04f, 0.008f, 2e-3, 5e-4, 1e-4, 3e-6], 0.05f);
	/// how fast reverb strength increases with range
	float reverbGainRangeK = 1 / 1500.0f;
	/// perlin noise cell sizes (two noise passes are added)
	int[2] perlinCellSize = [51, 23];
	/// perlin noise amplitudes (two noise passes are added)
	dB[2] perlinGain = [3.0f, 1.4f];
	/// sonar image will be black on this pixel intensity level
	dB zeroLevel = dB(seaNoiseIL(1200).val - 20.0f);
	/// when converting to ubyte, intensity levels will be scaled by this value
	float endScale = 1 / 50.0f;

	/// Slice horizontal resolution
	int getSliceResol() const
	{
		return (span / omniBeamCount * 360.0f).to!int;
	}
}


/// Component that builds active sonar ping image
final class ActiveSonar
{
	this(DsubsSoundOpenclCtx ctx, Transform2D trans, ref const ActiveSonarPrototype proto)
	{
		m_transform = trans;
		m_proto = proto;
		m_omniImage = FloatImage(ctx, proto.omniBeamCount, proto.maxSec * proto.radialRes);
		m_nextSliceImage = ByteImage(ctx, proto.getSliceResol(), proto.radialRes);
		m_nextSlice = new ubyte[m_nextSliceImage.size];
		m_maxRange = SOUND_SPD * proto.maxSec / 2;
		onPreSimulation += () { m_worldRotStart = m_transform.wrotation; };
		onPostSimulation += () { m_worldRotEnd = m_transform.wrotation; };
	}

	private
	{
		Transform2D m_transform;
		const ActiveSonarPrototype m_proto;
		bool m_active = true;
		bool m_hasSliceToSend = false;

		/// speed in knots at the start of integration
		float m_ktsStart = 0.0f;
		float m_ktsEnd = 0.0f;
		float m_worldRotStart = 0.0f;
		float m_worldRotEnd = 0.0f;
		float m_angVelStart = 0.0f;
		float m_angVelEnd = 0.0f;

		// precalculated parameters
		float m_maxRange;

		// tracked ping data:

		/// omnidirectional image with drawed reflectors and water noise
		FloatImage m_omniImage;
		float m_omiWrot;	/// world rotation at the start of ping
		bool m_pingJustStarted;
		dB m_curPingIlevel;		/// tracked ping intensity level
		/// Each simulation step we map part of omniImage to nextSlice
		ByteImage m_nextSliceImage;
		ubyte[] m_nextSlice;
		/// There are this many slices left in omniImage
		int m_slicesLeft = 0;
		int m_sliceOffset = 0;
		/// Serial number of current tracked ping
		int m_pingCounter = -1;
	}

	/// invoked by simulator before kinematic update happens
	Event!(void delegate()) onPreSimulation;
	/// invoked by simulator right after kinematic update happens
	Event!(void delegate()) onPostSimulation;

	/// set speed at the start of integration
	@property void ktsStart(float rhs)
	{
		m_ktsStart = rhs;
	}

	/// set angular velocity at the start of integration
	@property void angVelStart(float rhs)
	{
		m_angVelStart = rhs;
	}

	/// set speed at the end of integration
	@property void ktsEnd(float rhs)
	{
		m_ktsEnd = rhs;
	}

	@property void angVelEnd(float rhs)
	{
		m_angVelEnd = rhs;
	}

	@property bool active() const { return m_active; }
	@property void active(bool rhs)
	{
		m_active = rhs;
		m_hasSliceToSend = false;
	}

	@property bool hasSliceToSend() const { return m_hasSliceToSend; }
	@property bool canGenerateSlice() const { return (m_slicesLeft > 0); }
	@property int pingCounter() const { return m_pingCounter; }

	/// index of current to-send slice: [0 .. slicesInPing)
	@property int readySliceId() const { return (m_sliceOffset / m_proto.radialRes) - 1; }

	void skipSiceGeneration()
	{
		assert(m_slicesLeft > 0);
		m_slicesLeft--;
		m_sliceOffset += m_proto.radialRes;
		m_hasSliceToSend = false;
	}

	int startPing(dB ilevel)
	{
		enforce(ilevel <= m_proto.maxPeakIlevel && ilevel >= m_proto.minPeakIlevel,
			"desired ping intensity out of allowed interval");
		m_curPingIlevel = ilevel;
		if (m_pingJustStarted)
			return m_pingCounter;
		m_sliceOffset = 0;
		m_slicesLeft = m_proto.maxSec;
		m_hasSliceToSend = false;
		m_omiWrot = m_transform.wrotation;
		m_pingJustStarted = true;
		return (++m_pingCounter);
	}

	@property bool pingJustStarted() const { return m_pingJustStarted; }

	/// Given the range of all active reflectors on the map,
	/// imprint them on newly-created ping image
	void drawReflectors(RR)(CommandQueue q, RR reflectors)
	{
		assert(m_pingJustStarted);
		m_pingJustStarted = false;
		/// iterate over reflectors and build buffer for opencl
		PreparedReflector[] prepr;
		foreach (Reflector r; reflectors)
		{
			PreparedReflector pr;
			vec2d dir = r.transform.wposition - m_transform.wposition;
			pr.range = dir.length;
			if (pr.range > m_maxRange + max(r.m_proto.size[0], r.m_proto.size[1]))
				continue;
			pr.relBearing = clampAnglePi(courseAngle(dir) - m_transform.wrotation);
			r.calcForEmitter(m_transform.wposition, pr);
			prepr ~= pr;
		}
		// push reflectors to opencl
		Buffer reflectBuf = Buffer(q.ctx, PreparedReflector.sizeof * prepr.length);
		reflectBuf.enqueueFullWrite(q, prepr, null).release();
		// Create sibling texture that will be released at the end of this function
		FloatImage m_tmpImg = FloatImage(q.ctx, m_omniImage.w, m_omniImage.h);
		PingKernelParams pkparams = PingKernelParams(m_curPingIlevel,
			m_curPingIlevel + m_proto.antiPeakIlevelDiff, m_proto.pingDirPower);

		float omniRangePerRow = m_maxRange / m_proto.maxSec / m_proto.radialRes;

		// reflector pass
		Kernel k = q.mk_sonarReflectorPass;
		k.setArg(0, m_omniImage.mem);
		k.setArg(1, q.ctx.b_wrdks.mem);
		k.setArg(2, pkparams);	// pingParams
		k.setArg(3, m_proto.pingParams.effectiveFreq);		// pingFreq
		k.setArg(4, float(2 * PI));	// span
		k.setArg(5, omniRangePerRow);	// rangePerRow
		k.setArg(6, m_proto.dissMod);	// dissMod
		// reflParamNoise
		k.setArg(7, vec2f(m_proto.reflBearingNoise, m_proto.reflRangeNoise));
		k.setArg(8, reflectBuf.mem);
		k.setArg(9, prepr.length.to!int);
		k.setArg(10, uintSeed());	// seed
		k.enqueue(q, 2, null, [m_omniImage.w, m_omniImage.h], null, null);

		// reverberation pass
		Buffer reverbKbuf = Buffer(q.ctx, m_proto.reverbk.length * float.sizeof);
		reverbKbuf.enqueueFullWrite(q, m_proto.reverbk, null).release();

		k = q.mk_sonarReverbPass;
		k.setArg(0, m_omniImage.mem);
		k.setArg(1, m_tmpImg.mem);
		k.setArg(2, reverbKbuf.mem);
		k.setArg(3, m_proto.reverbk.length.to!int);
		k.setArg(4, m_proto.reverbGainRangeK);
		k.setArg(5, omniRangePerRow);
		k.enqueue(q, 2, null, [m_tmpImg.w, m_tmpImg.h], null, null);

		// isotropic pass
		k = q.mk_sonarIsotropicPass;
		k.setArg(0, m_tmpImg.mem);
		k.setArg(1, m_omniImage.mem);
		k.setArg(2, q.ctx.b_wrdks.mem);
		k.setArg(3, pkparams);	// pingParams
		k.setArg(4, m_proto.pingParams.effectiveFreq);		// pingFreq
		k.setArg(5, float(2 * PI));	// span
		k.setArg(6, m_proto.directivity);			// directivity
		k.setArg(7, m_proto.waterReflectivity);		// waterReflectivity
		k.setArg(8, omniRangePerRow);			// rangePerRow
		k.setArg(9, m_proto.dissMod);			// dissMod
		k.setArg(10, m_proto.perlinCellSize);		// perlCellSize
		k.setArg(11, m_proto.perlinGain);	// perlNoiseGain
		k.setArg(12, uintSeed());	// seed
		k.enqueue(q, 2, null, [m_omniImage.w, m_omniImage.h], null, null);
	}

	/// enqueue commands that render slite to byte buffer
	void startSliceGeneration(CommandQueue q)
	{
		assert(m_slicesLeft > 0);
		m_slicesLeft--;
		m_hasSliceToSend = true;

		Kernel k = q.mk_sonarSlicePass;
		k.setArg(0, m_omniImage.mem);
		k.setArg(1, m_nextSliceImage.mem);
		k.setArg(2, m_sliceOffset);	// yoffset
		k.setArg(3, float(dgr2rad(m_proto.span)));	// destSpan
		k.setArg(4, 1.0f);		// rangePerRowRatio

		vec2f relRots = vec2f(
			m_worldRotStart - m_omiWrot, m_worldRotEnd - m_omiWrot);
		k.setArg(5, relRots);	// relRotations
		k.setArg(6, vec2f(m_angVelStart, m_angVelEnd));		// angVels
		k.setArg(7, m_proto.flowNoiseGain);				// flowNoiseGain
		k.setArg(8, vec2f(m_ktsStart, m_ktsEnd));		// kts
		k.setArg(9, m_proto.pingParams.effectiveFreq);	// pingFreq
		k.setArg(10, m_proto.endScale);		// endScale
		k.setArg(11, m_proto.zeroLevel);		// zeroLevel
		k.setArg(12, m_proto.baseNoise);		// baseNoise
		k.setArg(13, uintSeed());			// seed
		k.enqueue(q, 2, null, [m_nextSliceImage.w, m_nextSliceImage.h], null, null);

		m_sliceOffset += m_proto.radialRes;

		m_nextSliceImage.enqueueRead(q, m_nextSlice, [0, 0],
			[m_nextSliceImage.w, m_nextSliceImage.h]).release();
	}

	/// Get last slice
	immutable(ubyte)[] getLastSlice() const
	{
		assert(m_hasSliceToSend);
		return cast(immutable) m_nextSlice;
	}
}


unittest
{
	DsubsSoundOpenclCtx ctx = s_clCtx;
	CommandQueue q = ctx.queue(0);
	auto sproto = ActiveSonarPrototype();
	ActiveSonar s = new ActiveSonar(ctx, new Transform2D(), sproto);
	s.angVelStart = 0.0f;
	s.ktsStart = 0.0f;
	s.angVelEnd = 0.0f;
	s.ktsEnd = 0.0f;
	s.onPreSimulation();
	s.onPostSimulation();
	Reflector refl = new Reflector(new Transform2D(),
		ReflectorPrototype(vec2f(50, 50), [-1, -1, -1]));
	refl.transform.position = vec2d(0, 2000);
	s.startPing(120);
	s.drawReflectors(q, [refl]);
	s.startSliceGeneration(q);
	q.finish();
}


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