module dsubs_sound.soundsource;

import std.algorithm;

import dsubs_common.event;

import dsubs_sound.common;
import dsubs_sound.filter;
import dsubs_sound.opencl;
import dsubs_sound.spectrum;
import dsubs_sound.water;
import dsubs_sound.modulation;
import dsubs_sound.image;


abstract class SoundSource
{
	private vec2d m_prevPos;

	/// world-space position
	@property vec2d position();

	/// return source position before kinematics integration
	final @property vec2d prevPos() const { return m_prevPos; }

	/// save current position of transform to m_prevPos
	final void savePrevPos() { m_prevPos = position; }

	/// Physical radius of emitting area. Affects tha halo size on
	/// close distances.
	@property float radius() const;

	/// Returns minimal omnidirectional factor at the range
	float minOmniFactor(float range) const;

	/// invoked by simulator before kinematic update happens
	Event!(void delegate()) onPreSimulation;
	/// invoked by simulator right after kinematic update happens
	Event!(void delegate(float dt)) onPostSimulation;

	/** Generate band intensity and time-domain signal(s) for a hydrophone.
	'onTdsReady' callback must be called in order to imprint the time-domain
	signal onto the listener. SoundSource is responsible for range-related
	signal attenuation.

	Note on band intensity - pressure relations:

	Ideal allpass hydrophone for intensity spectrum with all bins of value 1 watt
	expects from SoundSource a band sum value of GLOBAL_SRATE / 2.0f. You must reduceSum
	only the part of the spectrum that is specified by [minFreq; maxFreq].
	Hydrophone then expects sound source to pass tds to it that is produced
	directly via toTimeDomain method, that is it's mean square of pressure
	samples should be 1.0f / GLOBAL_SRATE for the abovementioned unit spectrum.
	*/
	void buildSignals(CommandQueue q,
		vec2d listenerPos, vec2d prevListenerPos,
		scope void delegate(Intensity* bandIntensitySumReady,
			Buffer* bandIntensitySumBuf, Tds* tds) onTdsReady,
		int minFreq, int maxFreq, bool needTds, float dissMod = 4.0f,
		FIRFilter* listenerFilter = null);
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
	this(Transform2D t, const PropellerSoundPrototype p)
	{
		m_transform = t;
		m_baseBBSpectrum = p.baseBBSpectrum;
		m_baseCavSpectrum = p.baseCavSpectrum;
		//m_am = templ.am;
		m_tm = TrochoidModulator(p.tmParams);
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
		Transform2D m_transform;

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

	override @property vec2d position() { return m_transform.wposition; }

	override @property float radius() const { return 1.5f * m_bladeRadius; }

	/// Update state at the beginning of kinematic simulation. rotFreq is shaft rotation
	/// frequency. waterSpeedStart is projection of water relative speed on shaft axis.
	void preUpdate(float shaftFreqStart, float waterSpeedStart)
	{
		assert(!isNaN(shaftFreqStart));
		assert(!isNaN(waterSpeedStart));
		m_shaftFreqStart = shaftFreqStart;
		m_normalVelStart = caclNormalVel(shaftFreqStart, waterSpeedStart);
		savePrevPos();
	}

	private float caclNormalVel(float freq, float waterSpeed) const
	{
		vec2f bladeVel = vec2f(0.0f, -freq * 2 * PI * m_bladeRadius);
		vec2f waterVel = bladeVel + vec2f(waterSpeed, 0.0f);
		vec2f bladeNormal = vec2f(-cos(m_bladeAoA), -sin(m_bladeAoA));
		return fabs(dot(bladeNormal, waterVel));
	}

	/// Modulator needs to know final rotation speed to simulate a smooth transition.
	void postUpdate(float endShaftFreq, float waterSpeedEnd, float dt)
	{
		assert(!isNaN(endShaftFreq));
		assert(!isNaN(waterSpeedEnd));
		m_shaftFreqEnd = endShaftFreq;
		m_normalVelEnd = caclNormalVel(endShaftFreq, waterSpeedEnd);
		m_tm.updateFundFreq(m_shaftFreqStart, m_shaftFreqEnd);
		m_tm.updateStartPhase(dt);
		m_transform.ensureNotDirty();
	}

	private float genISpec(CommandQueue q, float avgRange, float relBearing,
		ref ISpectrum dest, const ref ISpectrum source, int minFreq, int maxFreq,
		float kstart, float kend, float dissMod)
	{
		float kavg = (kstart.fabs + kend.fabs) / 2;
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

	override void buildSignals(CommandQueue q,
		vec2d listenerPos, vec2d prevListenerPos,
		scope void delegate(Intensity* bandIntensitySumReady,
			Buffer* bandIntensitySumBuf, Tds* tds) onTdsReady,
		int minFreq, int maxFreq, bool needTds, float dissMod = 1.0f,
		FIRFilter* listenerFilter = null)
	{
		assert(minFreq >= 1);
		assert(maxFreq <= ISpectrum.MAX_FREQ);
		float range = max(10.0f, (listenerPos - m_transform.wposition).length);
		float prevRange = max(10.0f, (prevListenerPos - prevPos).length);
		float avgRange = 0.5f * (range + prevRange);
		float relBearing =
			courseAngle(listenerPos - m_transform.wposition) - m_transform.wrotation;
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
		// broadband component
		float kavg = genISpec(q, avgRange, relBearing, q.s_ispec, *m_baseBBSpectrum,
			minFreq, maxFreq, freqCubeStart, freqCubeEnd, dissMod);
		if (needTds && kavg > 0.0f)
		{
			q.s_ispec.toTimeDomain(q, q.s_tds);
			doModulate(q, q.s_tds, kavg, freqCubeStart / pow(prevRange, 2),
				freqCubeEnd / pow(range, 2));
			onTdsReady(null, &q.s_bandSumBuf, &q.s_tds);
		}
		else
			onTdsReady(null, &q.s_bandSumBuf, null);
		// cavitation component
		kavg = genISpec(q, avgRange, relBearing, q.s_ispec, *m_baseCavSpectrum,
			minFreq, maxFreq, cavSqrStart, cavSqrEnd, dissMod);
		if (needTds && kavg > 0.0f)
		{
			q.s_ispec.toTimeDomain(q, q.s_tds);
			doModulate(q, q.s_tds, kavg, cavSqrStart / pow(prevRange, 2),
				cavSqrEnd / pow(range, 2));
			onTdsReady(null, &q.s_bandSumBuf, &q.s_tds);
		}
		else
			onTdsReady(null, &q.s_bandSumBuf, null);
	}
}


struct PrerecordedSoundPrototype
{
	VarTds* tds;
	float radius;
	dB addToIlevel;
}


final class PrerecordedSoundSource: SoundSource
{
	this(Transform2D t, PrerecordedSoundPrototype proto,
		size_t* destOffset)
	{
		m_transform = t;
		m_proto = proto;
		if (destOffset)
		{
			assert(*destOffset < GLOBAL_SRATE);
			m_destOffset = *destOffset;
		}
		else
			m_destOffset = uniform(0, GLOBAL_SRATE - 1);
	}

	private
	{
		Transform2D m_transform;
		PrerecordedSoundPrototype m_proto;
		size_t m_sourceOffset;
		size_t m_destOffset;
		size_t m_samplesLeft;
	}

	/// update internal offsets
	void onAfterAcoustics()
	{
		size_t usedSamples = GLOBAL_SRATE - m_destOffset;
		m_destOffset = 0;
		m_sourceOffset = min(m_proto.tds.length, m_sourceOffset + usedSamples);
		m_samplesLeft -= min(usedSamples, m_samplesLeft);
	}

	override @property vec2d position() { return m_transform.wposition; }

	override @property float radius() const { return m_proto.radius; }

	override float minOmniFactor(float range) const { return 0.0f; }

	override void buildSignals(CommandQueue q,
		vec2d listenerPos, vec2d prevListenerPos,
		scope void delegate(Intensity* bandIntensitySumReady,
			Buffer* bandIntensitySumBuf, Tds* tds) onTdsReady,
		int minFreq, int maxFreq, bool needTds, float dissMod,
		FIRFilter* listenerFilter)
	{
		assert(minFreq >= 1);
		assert(maxFreq <= ISpectrum.MAX_FREQ);
		float range = max(10.0f, (listenerPos - m_transform.wposition).length);
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
		q.ctx.waterFilter.filter(q,
			listenerFilter ? q.s_vartds2sec2 : q.s_vartds2sec,
			GLOBAL_SRATE, q.s_tds, 0, prevRange, range, dissMod);
		// now we apply the modulation, requested by range and the prototype.
		IntensityLevel ilevel = getILatRange(1, IntensityLevel(0.0f), range, dissMod);
		IntensityLevel prevIlevel = getILatRange(1, IntensityLevel(0.0f),
			prevRange, dissMod);
		modulateILevelInterp(q, q.s_tds,
			m_proto.addToIlevel + prevIlevel.val, m_proto.addToIlevel + ilevel.val);
		q.s_tds.reduceSumSquared(q, q.s_bandSumBuf,
			1.0f / (GLOBAL_SRATE * GLOBAL_SRATE / 2), 0, GLOBAL_SRATE);
		if (needTds)
			onTdsReady(null, &q.s_bandSumBuf, &q.s_tds);
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
		loadSpectrumFromImage(q, *cavSpec, "std_propeller_cav.png", 60.0f, 140.0f);
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


unittest
{
	PropellerSound ps = new PropellerSound(new Transform2D(), stdPropellerProto());
	ps.preUpdate(2.0f, 0.0f);
	trace("2Hz propeller normalVel on 0 m/s: ", ps.m_normalVelStart);
	ps.preUpdate(2.0f, 5.0f);
	trace("2Hz propeller normalVel on 5 m/s: ", ps.m_normalVelStart);
	ps.preUpdate(2.0f, 15.0f);
	trace("2Hz propeller normalVel on 15 m/s: ", ps.m_normalVelStart);
}

unittest
{
	DsubsSoundOpenclCtx ctx = s_clCtx;
	CommandQueue q = ctx.queue(0);
	ISpectrum spec = ISpectrum(q, 2.0f);
	float bandSum;
	Buffer sumBuf = Buffer(ctx, float.sizeof);
	spec.reduceSum(q, sumBuf);
	sumBuf.enqueueFullRead(q, &bandSum, null).waitFor();
	assert(fabs(bandSum - GLOBAL_SRATE) < 1e-3);
	Tds timeDomain = Tds(q, 0.0f);
	spec.toTimeDomain(q, timeDomain);
	float[] signal;
	signal.length = GLOBAL_SRATE;
	timeDomain.read(q, signal);
	float sqr = signal.map!(a => a * a).sum();
	trace("sum of quared pressure samples of 2-watt intensity spectrum: ", sqr);
	assert(fabs(sqr - 2.0f) < 1e-3);
}

unittest
{
	DsubsSoundOpenclCtx ctx = s_clCtx;
	CommandQueue q = ctx.queue(0);
	ISpectrum spec = ISpectrum(q, GLOBAL_SRATE);
	float bandSum;
	Buffer sumBuf = Buffer(ctx, float.sizeof);
	spec.reduceSum(q, sumBuf);
	sumBuf.enqueueFullRead(q, &bandSum, null).waitFor();
	assert(fabs(bandSum - GLOBAL_SRATE * GLOBAL_SRATE / 2) < 1e-3);
	Tds timeDomain = Tds(q, 0.0f);
	spec.toTimeDomain(q, timeDomain);
	float[] signal;
	signal.length = GLOBAL_SRATE;
	timeDomain.read(q, signal);
	float msqr = signal.map!(a => a * a).sum() / GLOBAL_SRATE;
	trace("mean square of pressure samples of GLOBAL_SRATE ",
		"intensity spectrum: ", msqr);
	assert(fabs(msqr - 1.0f) < 1e-3);
}

unittest
{
	DsubsSoundOpenclCtx ctx = s_clCtx;
	CommandQueue q = ctx.queue(0);
	PropellerSound snd = new PropellerSound(new Transform2D(), stdPropellerProto());
	snd.preUpdate(1.0f, 10.0f);
	snd.postUpdate(1.0f, 10.0f, 1.0f);

	void onTdsReady(Intensity* bandIntensitySumReady, Buffer* bandIntensitySumBuf, Tds* tds)
	{
		trace("onTdsReady called");
		assert(tds is null);
		float bandSum = -1.0f;
		bandIntensitySumBuf.enqueueFullRead(q, &bandSum, null).waitFor();
		trace("bandSum = ", bandSum);
		assert(bandSum != -1.0f);
		assert(!isNaN(bandSum));
	}

	snd.buildSignals(q, vec2d(1000.0, 0), vec2d(1000.0, 0),
		&onTdsReady, 500, 2048, false, 4.0f);
}