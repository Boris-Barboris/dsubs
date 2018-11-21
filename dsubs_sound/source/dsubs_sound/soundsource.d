module dsubs_sound.soundsource;

import std.algorithm;

import dsubs_common.event;

import dsubs_sound.common;
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

	/// invoked by simulator before kinematic update happens
	Event!(void delegate()) onPreSimulation;
	/// invoked by simulator right after kinematic update happens
	Event!(void delegate(float dt)) onPostSimulation;

	/// Generate band intensity and time-domain signal(s) for a hydrophone
	void buildSignals(CommandQueue q, vec2d listenerPos,
		scope void delegate(ref Buffer bandIntensityBuf, Tds* tds) onSignalReady,
		int minFreq, int maxFreq, bool needTds, float dissMod = 1.0f);
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

	private float genISpec(CommandQueue q, float range, float relBearing,
		ref ISpectrum dest, const ref ISpectrum source, int minFreq, int maxFreq,
		float kstart, float kend, float dissMod = 1.0f)
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
		k.setArg(3, range);
		k.setArg(4, dissMod);
		k.setArg(5, imult);
		k.setArg(6, m_rngSpan);
		k.setArg(7, uintSeed());
		k.enqueue(q, 1, [minFreq - 1], [maxFreq - minFreq + 1], null, null);

		// float[GLOBAL_SRATE / 2] ispecDump;
		// (cast(ISpectrum) dest).enqueueRead(q, ispecDump[]).waitFor();
		// trace("ispecDump: ", ispecDump);

		// bin sum
		dest.reduceSum(q, q.s_bandSumBuf, minFreq, maxFreq);

		return kavg;
	}

	private void doModulate(CommandQueue q, ref Tds tds,
		float kavg, float kstart, float kend)
	{
		assert(kavg > 0.0f);
		modulateIInterp(q, tds, kstart / kavg, kend / kavg);
		m_tm.modulate(q, tds);
	}

	override void buildSignals(CommandQueue q, vec2d listenerPos,
		scope void delegate(ref Buffer bandIntensityBuf, Tds* tds) onSignalReady,
		int minFreq, int maxFreq, bool needTds, float dissMod = 1.0f)
	{
		assert(minFreq >= 1);
		assert(maxFreq <= ISpectrum.MAX_FREQ);
		float range = (listenerPos - m_transform.wposition).length;
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
		float kavg = genISpec(q, range, relBearing, q.s_ispec, *m_baseBBSpectrum,
			minFreq, maxFreq, freqCubeStart, freqCubeEnd, dissMod);
		if (needTds && kavg > 0.0f)
		{
			q.s_ispec.toTimeDomain(q, q.s_tds);
			doModulate(q, q.s_tds, kavg, freqCubeStart, freqCubeEnd);
			onSignalReady(q.s_bandSumBuf, &q.s_tds);
		}
		else
			onSignalReady(q.s_bandSumBuf, null);
		// cavitation component
		kavg = genISpec(q, range, relBearing, q.s_ispec, *m_baseCavSpectrum,
			minFreq, maxFreq, cavSqrStart, cavSqrEnd, dissMod);
		if (needTds && kavg > 0.0f)
		{
			q.s_ispec.toTimeDomain(q, q.s_tds);
			doModulate(q, q.s_tds, kavg, cavSqrStart, cavSqrEnd);
			onSignalReady(q.s_bandSumBuf, &q.s_tds);
		}
		else
			onSignalReady(q.s_bandSumBuf, null);
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
		loadSpectrumFromImage(q, *bbSpec, "std_propeller.png", 80.0f, 140.0f);
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
	ISpectrum spec = ISpectrum(q, 1.0f);
	float sum;
	Buffer sumBuf = Buffer(ctx, float.sizeof);
	spec.reduceSum(q, sumBuf);
	sumBuf.enqueueFullRead(q, &sum, null).waitFor();
	assert(fabs(sum - GLOBAL_SRATE / 2.0) < 1e-3);
}

unittest
{
	DsubsSoundOpenclCtx ctx = s_clCtx;
	CommandQueue q = ctx.queue(0);
	PropellerSound snd = new PropellerSound(new Transform2D(), stdPropellerProto());
	snd.preUpdate(1.0f, 10.0f);
	snd.postUpdate(1.0f, 10.0f, 1.0f);

	void onSignalReady(ref Buffer bandIntensityBuf, Tds* tds)
	{
		trace("onSignalReady called");
		assert(tds is null);
		float bandSum = -1.0f;
		bandIntensityBuf.enqueueFullRead(q, &bandSum, null).waitFor();
		trace("bandSum = ", bandSum);
		assert(bandSum != -1.0f);
		assert(!isNaN(bandSum));
	}

	snd.buildSignals(q, vec2d(1000.0, 0), &onSignalReady, 500, 2048, false, 4.0f);
}