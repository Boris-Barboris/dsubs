module dsubs_sound.soundsource;

import std.algorithm;

import dsubs_common.event;
import dsubs_common.math;

import dsubs_sound.common;
import dsubs_sound.filter;
import dsubs_sound.opencl;
import dsubs_sound.spectrum;
import dsubs_sound.water;
import dsubs_sound.modulation;
import dsubs_sound.image;


/// Spherical sound emitter.
abstract class SoundSource
{
	private
	{
		vec2d m_prevPos;
		Transform2D m_transform;
	}

	/// Abstract owner
	Object owner;

	this(Transform2D t)
	{
		m_transform = t;
		savePrevPos();
		onPreKinematics += &savePrevPos;
	}

	/// world-space position of emitter center
	final @property vec2d position() { return m_transform.wposition; }

	/// transform, assigned to the source
	final @property Transform2D transform() { return m_transform; }

	/// return source position before kinematics update
	final @property vec2d prevPos() const { return m_prevPos; }

	/// save current position of transform to m_prevPos
	final void savePrevPos() { m_prevPos = position; }

	/// Physical radius of emitting area, meters. Affects waterfall halo size on
	/// close distances.
	@property float radius() const;

	/// Returns minimal omnidirectional factor at the specified range.
	float minOmniFactor(float range) const;

	/// Must be invoked by simulator before kinematic update.
	Event!(void delegate()) onPreKinematics;
	/// Must be invoked by simulator right after kinematic update.
	Event!(void delegate(float dt)) onPostKinematics;
	/// Must be invoked by simulator in postAcousticsUpdate.
	Event!(void delegate()) onPostAcoustics;

	/** Generate band intensity and time-domain signal(s) for a hydrophone.
	'onTdsReady' callback must be called in order to imprint the time-domain
	signal onto the listener. SoundSource is responsible for signal distortion
	and weakening, caused by range and water. Listener's properties are respected
	by accounting for it's passband.

	Note on band intensity - pressure relations:

	Ideal allpass hydrophone for emitter's intensity spectrum with all bins of value 1 watt
	expects from SoundSource a band sum value of GLOBAL_SRATE / 2.0f. You must reduceSum
	only the part of the spectrum that is specified by [minFreq; maxFreq].
	Hydrophone then expects sound source to pass tds to it that is produced
	directly via toTimeDomain method, meaning it's mean square of pressure
	samples should be 1.0f / GLOBAL_SRATE for the abovementioned unit spectrum.
	*/
	void buildSignals(
		CommandQueue q,
		vec2d listenerPos,		// hydrophone's world-space position.
		vec2d prevListenerPos,	// hydrophone's world-space position before the last kinematics update.
		scope void delegate(
				Intensity* bandIntensitySumReady,	// if can be calculated on cpu, pass it here.
				Buffer* bandIntensitySumBuf,		// otherwise, pass reference to buffer.
				Tds* tds)							// should pass when 'needTds' is true.
			onTdsReady,			// call at most Hydrophone.SourcePrecalc.MAX_COMPONENTS times.
		int minFreq, int maxFreq,			// listener's passband.
		bool needTds,						// wether tds generation is requested by listener
		float dissMod = 4.0f,				// water dissipation modifier
		FIRFilter* listenerFilter = null,
		bool logMore = false);
		// filter, used to implement listener's passband. If the
		// sound source does not work in frequency domain, this filter should be used by the source to clamp itself to listener's passband.
}


struct PropellerSoundPrototype
{
	const(ISpectrum)* baseBBSpectrum;
	const(ISpectrum)* baseCavSpectrum;
	immutable(TrochoidModulatorParams)* tmParams;
	float bladeRadius;
	float bladeAoA;
	float critNormalVel;
	float rngSpan = 0.0f;
	float aftIntensity = 1.0f;
}


final class PropellerSound: SoundSource
{
	this(CommandQueue q, Transform2D t, const PropellerSoundPrototype p)
	{
		super(t);
		m_baseBBSpectrum = p.baseBBSpectrum;
		m_baseCavSpectrum = p.baseCavSpectrum;
		//m_am = templ.am;
		synchronized(q)
		{
			m_tm = TrochoidModulator(q, p.tmParams);
		}
		m_tm.randomizePhase();
		m_bladeRadius = p.bladeRadius;
		m_bladeAoA = p.bladeAoA;
		m_critNormalVel = p.critNormalVel;
		m_rngSpan = p.rngSpan;
		m_aftIntensity = p.aftIntensity;
		assert(m_aftIntensity >= 0.0f && m_aftIntensity <= 1.0f);
	}

	private
	{
		// Base reference intensity spectrum of non-cavitating component on 1Hz
		const ISpectrum* m_baseBBSpectrum;
		// Base reference intensity spectrum of cavitation noise component on
		// criticalNormalVel + 1m/s
		const ISpectrum* m_baseCavSpectrum;

		// AmplitudeModulatorParams m_am;
		TrochoidModulator m_tm;
		float m_bladeRadius;
		float m_bladeAoA;
		float m_shaftFreqStart, m_shaftFreqEnd;
		float m_normalVelStart, m_normalVelEnd;

		// cavitation starts at this water normal velocity
		float m_critNormalVel;
		float m_rngSpan;
		float m_aftIntensity;
	}

	override @property float radius() const { return 1.5f * m_bladeRadius; }

	/// Update state before kinematic update. rotFreq is shaft rotation
	/// frequency. waterSpeedStart is projection of water relative speed on shaft axis.
	void preUpdate(float shaftFreqStart, float waterSpeedStart)
	{
		assert(!isNaN(shaftFreqStart));
		assert(!isNaN(waterSpeedStart));
		m_shaftFreqStart = shaftFreqStart;
		m_normalVelStart = caclNormalVel(shaftFreqStart, waterSpeedStart,
			m_bladeRadius, m_bladeAoA);
	}

	private static float caclNormalVel(float freq, float waterSpeed,
		float bladeRadius, float bladeAoA)
	{
		vec2f bladeVel = vec2f(0.0f, -freq * 2 * PI * bladeRadius);
		vec2f waterVel = bladeVel + vec2f(waterSpeed, 0.0f);
		vec2f bladeNormal = vec2f(-cos(bladeAoA), -sin(bladeAoA));
		return fabs(dot(bladeNormal, waterVel));
	}

	/// Modulator needs to know final rotation speed to simulate a smooth transition.
	/// This shuld be called after kinematic's update and after propulsor's update.
	void postUpdate(float endShaftFreq, float waterSpeedEnd, float dt)
	{
		assert(!isNaN(endShaftFreq));
		assert(!isNaN(waterSpeedEnd));
		m_shaftFreqEnd = endShaftFreq;
		m_normalVelEnd = caclNormalVel(endShaftFreq, waterSpeedEnd,
			m_bladeRadius, m_bladeAoA);
		m_tm.updateFundFreq(m_shaftFreqStart, m_shaftFreqEnd);
		m_tm.updateStartPhase(dt);
		m_transform.ensureNotDirty();
	}

	private float genISpec(CommandQueue q, float avgRange, float relBearing,
		ref ISpectrum dest, const ref ISpectrum source, int minFreq, int maxFreq,
		float kavg, float dissMod)
	{
		float bearingK = 1.0f -
			0.5f * (1.0f - m_aftIntensity) * (cos(2.0f * relBearing) + 1.0f);
		float imult = kavg * bearingK;
		//trace("imult = ", imult);
		assert(!isNaN(imult));
		assert(!isNaN(m_rngSpan));
		// first we zero out dest
		dest.patch(q, 0.0f);
		// then we dispatch ispectrum conversion
		Kernel k = q.mk_propellerGenISpec;
		k.setArg(0, source.mem);
		k.setArg(1, dest.mem);
		k.setArg(2, q.ctx.b_wrdks.mem);
		k.setArg(3, avgRange);
		k.setArg(4, dissMod);
		k.setArg(5, imult);
		k.setArg(6, m_rngSpan);
		k.setArg(7, uintSeed());
		k.enqueue(q, 1, [minFreq - 1], [maxFreq - minFreq + 1], null, null);

		// trace(cast(void*) this, ", kavg = ", kavg, ", avgRange = ", avgRange,
		// 	", imult = ", imult);

		// bin sum
		dest.reduceSum(q, q.s_bandSumBuf, minFreq, maxFreq);

		// kavg is divided on the square of avgRange to use this in later
		// range-related modulation
		return kavg / pow(avgRange, 2);
	}

	override float minOmniFactor(float range) const
	{
		/// regular propellers have no business being omni
		return 0.0f;
	}

	private void doModulate(CommandQueue q, ref Tds tds,
		float kavg, float kstart, float kend)
	{
		assert(kavg > 0.0f);
		modulateIInterp(q, tds, kstart / kavg, kend / kavg);
		m_tm.modulate(q, tds);
	}

	static float estCavitationShaftFreq(
		const PropellerSoundPrototype proto,
		float waterSpeed = 0.0f)
	{
		float criticalSpdFunc(float shaftFreq)
		{
			float normalVel = caclNormalVel(shaftFreq, waterSpeed,
				proto.bladeRadius, proto.bladeAoA);
			return proto.critNormalVel - normalVel;
		}

		return binarySearch(&criticalSpdFunc, 0.0, 1.0f, 10);
	}

	// same but more dynamic, accounts for submarine speed
	static float estCavitationSustainedSpeed(
		const PropellerSoundPrototype proto,
		float delegate(float freq) freq2waterSpeed)
	{
		float criticalSpdFunc(float shaftFreq)
		{
			float normalVel = caclNormalVel(
				shaftFreq, freq2waterSpeed(shaftFreq),
				proto.bladeRadius, proto.bladeAoA);
			return proto.critNormalVel - normalVel;
		}

		float cavFreq = binarySearch(&criticalSpdFunc, 0.0, 1.0f, 10);
		return freq2waterSpeed(cavFreq);
	}

	override void buildSignals(CommandQueue q,
		vec2d listenerPos, vec2d prevListenerPos,
		scope void delegate(Intensity* bandIntensitySumReady,
			Buffer* bandIntensitySumBuf, Tds* tds) onTdsReady,
		int minFreq, int maxFreq, bool needTds, float dissMod = 1.0f,
		FIRFilter* listenerFilter = null, bool logMore = false)
	{
		assert(minFreq >= 1);
		assert(maxFreq <= ISpectrum.MAX_FREQ);
		float range = max(10.0f, (listenerPos - m_transform.wposition).length);
		float prevRange = max(10.0f, (prevListenerPos - prevPos).length);
		float avgRange = 0.5f * (range + prevRange);
		assert(!isNaN(avgRange));
		float relBearing =
			clampAnglePi(
				courseAngle(listenerPos - m_transform.wposition) -
				m_transform.wrotation);
		// now actual power calculation
		float freqCubeStart = pow(m_shaftFreqStart, 3);
		assert(!isNaN(freqCubeStart));
		float freqCubeEnd = pow(m_shaftFreqEnd, 3);
		assert(!isNaN(freqCubeEnd));
		bool cavitation = fabs(m_normalVelStart) > m_critNormalVel;
		float cavSqrStart = cavitation ?
			(m_normalVelStart - m_critNormalVel) * fabs(m_normalVelStart - m_critNormalVel) :
			0.0f;
		assert(!isNaN(cavSqrStart));
		cavitation = fabs(m_normalVelEnd) > m_critNormalVel;
		float cavSqrEnd = cavitation ?
			(m_normalVelEnd - m_critNormalVel) * fabs(m_normalVelEnd - m_critNormalVel) :
			0.0f;
		assert(!isNaN(cavSqrEnd));
		float kavg = 0.5f * (freqCubeStart.fabs + freqCubeEnd.fabs);
		// broadband component
		if (kavg > 0.0f)
		{
			float kavgScaled = genISpec(q, avgRange, relBearing, q.s_ispec,
				*m_baseBBSpectrum, minFreq, maxFreq, kavg, dissMod);
			assert(!isNaN(kavgScaled));
			if (logMore)
			{
				trace(cast(void*) this,
						", source = ", this.owner.to!string,
						", kavg = ", kavg,
						", avgRange = ", avgRange,
						", dissMod = ", dissMod,
						", relBearing = ", relBearing,
						", kavgScaled = ", kavgScaled);
			}
			if (needTds)
			{
				Tds* tds = new Tds(q.ctx);
				q.s_ispec.toTimeDomain(q, *tds);
				doModulate(q, *tds, kavgScaled, freqCubeStart / pow(prevRange, 2),
					freqCubeEnd / pow(range, 2));
				onTdsReady(null, &q.s_bandSumBuf, tds);
			}
			else
				onTdsReady(null, &q.s_bandSumBuf, null);
		}
		// cavitation component
		kavg = 0.5f * (cavSqrStart.fabs + cavSqrEnd.fabs);
		if (kavg > 0.0f)
		{
			float kavgScaled = genISpec(q, avgRange, relBearing, q.s_ispec,
				*m_baseCavSpectrum, minFreq, maxFreq, kavg, dissMod);
			assert(!isNaN(kavgScaled));
			if (logMore)
			{
				trace(cast(void*) this,
						", source = ", this.owner.to!string,
						", kavg = ", kavg,
						", avgRange = ", avgRange,
						", dissMod = ", dissMod,
						", relBearing = ", relBearing,
						", kavgScaled = ", kavgScaled);
			}
			if (needTds)
			{
				Tds* tds = new Tds(q.ctx);
				q.s_ispec.toTimeDomain(q, *tds);
				doModulate(q, *tds, kavgScaled, cavSqrStart / pow(prevRange, 2),
					cavSqrEnd / pow(range, 2));
				onTdsReady(null, &q.s_bandSumBuf, tds);
			}
			else
				onTdsReady(null, &q.s_bandSumBuf, null);
		}
	}
}


/// Sound source that can be exhausted.
abstract class FiniteSoundSource: SoundSource
{
	this(Transform2D t) { super(t); }

	/// true when there will be no more sound.
	@property bool finished();
}

/// Sound source with fixed recording length.
abstract class FixedLengthSoundSource: FiniteSoundSource
{
	this(Transform2D t, size_t totalSamples, const(size_t)* sampleOffset = null)
	{
		super(t);
		m_totalSamples = totalSamples;
		assert(samplesLeft > 0);
		if (sampleOffset)
		{
			assert(*sampleOffset < GLOBAL_SRATE);
			m_destOffset = *sampleOffset;
		}
		else
			m_destOffset = uniform(0, GLOBAL_SRATE - 1);
		onPostAcoustics += &updateOffsets;
	}

	protected
	{
		size_t m_totalSamples;
		size_t m_sourceOffset;
		size_t m_destOffset;
	}

	final @property size_t totalSamples() const { return m_totalSamples; }

	/// when zero, recording is over and should be disposed of.
	final @property size_t samplesLeft() const { return m_totalSamples - m_sourceOffset; }

	final override @property bool finished() { return samplesLeft == 0; }

	/// move offsets one second further.
	private void updateOffsets()
	{
		size_t usedSamples = GLOBAL_SRATE - m_destOffset;
		m_destOffset = 0;
		m_sourceOffset = min(m_totalSamples, m_sourceOffset + usedSamples);
	}
}


struct PrerecordedSoundPrototype
{
	VarTds* tds;
	float radius;
	dB addToIlevel = 0.0f;
	float minOmniFactor = 0.0f;
}


final class PrerecordedSoundSource: FixedLengthSoundSource
{
	this(Transform2D t, PrerecordedSoundPrototype proto, size_t* sampleOffset = null)
	{
		super(t, proto.tds.length, sampleOffset);
		m_proto = proto;
	}

	private
	{
		PrerecordedSoundPrototype m_proto;
	}

	override @property float radius() const { return m_proto.radius; }

	override float minOmniFactor(float range) const { return m_proto.minOmniFactor; }

	override void buildSignals(CommandQueue q,
		vec2d listenerPos, vec2d prevListenerPos,
		scope void delegate(Intensity* bandIntensitySumReady,
			Buffer* bandIntensitySumBuf, Tds* tds) onTdsReady,
		int minFreq, int maxFreq, bool needTds, float dissMod,
		FIRFilter* listenerFilter, bool logMore = false)
	{
		assert(minFreq >= 1);
		assert(maxFreq <= ISpectrum.MAX_FREQ);
		float range = max(10.0f, (listenerPos - position).length);
		float prevRange = max(10.0f, (prevListenerPos - prevPos).length);
		float avgRange = 0.5f * (range + prevRange);
		// copy active part of the signal to separate staging vartds and apply
		// listener's filter. We need two seconds of the data to apply two
		// filters consequenctly instead of one.
		q.s_vartds2sec.fill(q, 0.0f);
		// q.s_vartds2sec is filled to have previous and current second data of
		// the m_proto.tds.
		ptrdiff_t prevSourceOffset = m_sourceOffset - GLOBAL_SRATE;
		size_t prevDestOffset = m_destOffset;
		if (prevSourceOffset < 0)
		{
			prevDestOffset += -prevSourceOffset;
			prevSourceOffset = 0;
		}
		m_proto.tds.copyTo(q, q.s_vartds2sec,
			prevSourceOffset.to!size_t, prevDestOffset);
		// first we apply listener's filter. No need to filter whole 2 seconds,
		// only 1 second + number of filter taps are allright.
		if (listenerFilter)
			listenerFilter.filter(q, q.s_vartds2sec,
				GLOBAL_SRATE - q.ctx.waterFilter.tapCount,
				GLOBAL_SRATE - q.ctx.waterFilter.tapCount, q.s_vartds2sec2);
		// second we apply water filter
		Tds* tds = new Tds(q.ctx);
		q.ctx.waterFilter.filter(q,
			listenerFilter ? q.s_vartds2sec2 : q.s_vartds2sec,
			GLOBAL_SRATE, *tds, 0, prevRange, range, dissMod);
		// now we apply the modulation, requested by range and the prototype.
		IntensityLevel ilevel = getILatRange(1, IntensityLevel(0.0f), range, dissMod);
		IntensityLevel prevIlevel = getILatRange(1, IntensityLevel(0.0f),
			prevRange, dissMod);
		modulateILevelInterp(q, *tds,
			m_proto.addToIlevel + prevIlevel.val, m_proto.addToIlevel + ilevel.val);
		// hydrophone contract
		tds.reduceSumSquared(q, q.s_bandSumBuf,
			GLOBAL_SRATE / 2.0f, 0, GLOBAL_SRATE);
		if (needTds)
			onTdsReady(null, &q.s_bandSumBuf, tds);
		else
			onTdsReady(null, &q.s_bandSumBuf, null);
	}
}


version (unittest)
{

	PropellerSoundPrototype stdPropellerProto()
	{
		DsubsSoundOpenclCtx ctx = s_clCtx;
		CommandQueue q = ctx.queue(0);
		PropellerSoundPrototype tmpl;
		ISpectrum* bbSpec = new ISpectrum(ctx);
		loadSpectrumFromImage(q, *bbSpec, "std_propeller.png", 60.0f, 135.0f);
		bbSpec.addUniformNoise(q, 0.5f);
		tmpl.baseBBSpectrum = bbSpec;
		ISpectrum* cavSpec = new ISpectrum(ctx);
		loadSpectrumFromImage(q, *cavSpec, "std_propeller_cav.png", 70.0f, 150.0f);
		cavSpec.addUniformNoise(q, 0.5f);
		tmpl.baseCavSpectrum = cavSpec;
		TrochoidModulatorParams* tmParams = new TrochoidModulatorParams();
		*tmParams = stdTrochParams();
		tmpl.tmParams = cast(immutable) tmParams;
		tmpl.bladeRadius = 4.2f;
		tmpl.bladeAoA = dgr2rad(30.0);
		tmpl.critNormalVel = 5.0f;
		tmpl.rngSpan = 0.03f;
		tmpl.aftIntensity = 0.4f;
		return tmpl;
	}

}


// unittest
// {
// 	PropellerSound ps = new PropellerSound(new Transform2D(), stdPropellerProto());
// 	ps.preUpdate(2.0f, 0.0f);
// 	trace("2Hz propeller normalVel on 0 m/s: ", ps.m_normalVelStart);
// 	ps.preUpdate(2.0f, 5.0f);
// 	trace("2Hz propeller normalVel on 5 m/s: ", ps.m_normalVelStart);
// 	ps.preUpdate(2.0f, 15.0f);
// 	trace("2Hz propeller normalVel on 15 m/s: ", ps.m_normalVelStart);
// }

// unittest
// {
// 	DsubsSoundOpenclCtx ctx = s_clCtx;
// 	CommandQueue q = ctx.queue(0);
// 	ISpectrum spec = ISpectrum(q, 2.0f);
// 	float bandSum;
// 	Buffer sumBuf = Buffer(ctx, float.sizeof);
// 	spec.reduceSum(q, sumBuf);
// 	sumBuf.enqueueFullRead(q, &bandSum, null).waitFor();
// 	assert(fabs(bandSum - GLOBAL_SRATE) < 1e-3);
// 	Tds timeDomain = Tds(q, 0.0f);
// 	spec.toTimeDomain(q, timeDomain);
// 	float[] signal;
// 	signal.length = GLOBAL_SRATE;
// 	timeDomain.read(q, signal);
// 	float sqr = signal.map!(a => a * a).sum();
// 	trace("sum of quared pressure samples of 2-watt intensity spectrum: ", sqr);
// 	assert(fabs(sqr - 2.0f) < 1e-3);
// }

// unittest
// {
// 	DsubsSoundOpenclCtx ctx = s_clCtx;
// 	CommandQueue q = ctx.queue(0);
// 	ISpectrum spec = ISpectrum(q, GLOBAL_SRATE);
// 	float bandSum;
// 	Buffer sumBuf = Buffer(ctx, float.sizeof);
// 	spec.reduceSum(q, sumBuf);
// 	sumBuf.enqueueFullRead(q, &bandSum, null).waitFor();
// 	assert(fabs(bandSum - GLOBAL_SRATE * GLOBAL_SRATE / 2) < 1e-3);
// 	Tds timeDomain = Tds(q, 0.0f);
// 	spec.toTimeDomain(q, timeDomain);
// 	float[] signal;
// 	signal.length = GLOBAL_SRATE;
// 	timeDomain.read(q, signal);
// 	float msqr = signal.map!(a => a * a).sum() / GLOBAL_SRATE;
// 	trace("mean square of pressure samples of GLOBAL_SRATE ",
// 		"intensity spectrum: ", msqr);
// 	assert(fabs(msqr - 1.0f) < 1e-3);
// }

// unittest
// {
// 	DsubsSoundOpenclCtx ctx = s_clCtx;
// 	CommandQueue q = ctx.queue(0);
// 	PropellerSound snd = new PropellerSound(new Transform2D(), stdPropellerProto());
// 	snd.preUpdate(1.0f, 10.0f);
// 	snd.postUpdate(1.0f, 10.0f, 1.0f);

// 	void onTdsReady(Intensity* bandIntensitySumReady, Buffer* bandIntensitySumBuf, Tds* tds)
// 	{
// 		trace("onTdsReady called");
// 		assert(tds is null);
// 		float bandSum = -1.0f;
// 		bandIntensitySumBuf.enqueueFullRead(q, &bandSum, null).waitFor();
// 		trace("bandSum = ", bandSum);
// 		assert(bandSum != -1.0f);
// 		assert(!isNaN(bandSum));
// 	}

// 	snd.buildSignals(q, vec2d(1000.0, 0), vec2d(1000.0, 0),
// 		&onTdsReady, 500, 2048, false, 4.0f);
// }