module dsubs_sound.soundsource;

import std.algorithm;

import dsubs_common.event;

import dsubs_sound.common;
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

	/// Generate band intensity and time-domain signal(s) for a listener
	void buildSignals(vec2d listenerPos,
		scope void delegate(float bandIntensity, TimeDomainSignal tds) onSignalReady,
		int minFreq, int maxFreq, bool needTds, float dissMod = 1.0f) const;
}


struct PropellerSoundPrototype
{
	IntensitySpectrum baseBBSpectrum;
	IntensitySpectrum baseCavSpectrum;
	// AmplitudeModulatorParams am;
	ThrachioidModulatorParams tm;
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
		m_tm = p.tm;
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
		const IntensitySpectrum m_baseBBSpectrum;
		// Base reference intensity spectrum of cavitation noise component on
		// criticalNormalVel + 1m/s
		const IntensitySpectrum m_baseCavSpectrum;

		// AmplitudeModulatorParams m_am;
		ThrachioidModulatorParams m_tm;
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
		m_tm.updateStartPhase(dt, endShaftFreq);
		m_transform.ensureNotDirty();
	}

	private void genISpec(float range, float relBearing, IntensitySpectrum dest,
		const IntensitySpectrum source, int minFreq, int maxFreq,
		float kstart, float kend, float dissMod = 1.0f) const
	{
		float kavg = (kstart.fabs + kend.fabs) / 2;
		float bearingK = 1.0f - 0.5f * (1.0f - m_aftIntensity) * (cos(2.0f * relBearing) + 1.0f);
		float rangeDb = toDb(range * range);
		for (int i = minFreq; i < maxFreq; i++)
		{
			float output = source.bins[i] * kavg;
			assert(!isNaN(output));
			// apply linear-space randomization
			output += output * uniform(-m_rngSpan, m_rngSpan);
			// apply bearing multiplier
			output *= bearingK;
			// now we apply water sound loss
			IntensityLevel outputDb = IntensityLevel(output.toDb());
			outputDb = getILatRange2(i, outputDb, range, rangeDb, dissMod);
			dest.bins[i] = outputDb.toLinear();
		}
	}

	private TimeDomainSignal genTds(IntensitySpectrum ispec, IModulator modulator) const
	{
		ensureTlsCache();
		s_stageIspec.genSpectrum(s_stageSpectrum);
		s_stageSpectrum.toTimeDomain(s_fftCache, s_stageTds);
		if (modulator)
			modulator.modulate(s_stageTds);
		return s_stageTds;
	}

	private IModulator genChainModulator(float kstart, float kend, IModulator mod) const
	{
		IntensityInterpolator ii = new IntensityInterpolator();
		float kavg = (kstart.fabs + kend.fabs) / 2;
		if (kavg != 0.0f)
		{
			ii.startIntensityMult = kstart / kavg;
			ii.endIntensityMult = kend / kavg;
		}
		return new ChainModulator(cast(IModulator[]) [mod, ii]);
	}

	override void buildSignals(vec2d listenerPos,
		scope void delegate(float bandIntensity, TimeDomainSignal tds) onSignalReady,
		int minFreq, int maxFreq, bool needTds, float dissMod = 1.0f) const
	{
		assert(m_baseBBSpectrum.bins.length == m_baseCavSpectrum.bins.length);
		assert(m_baseBBSpectrum.freqRes == m_baseCavSpectrum.freqRes);
		s_stageIspec.freqRes = m_baseBBSpectrum.freqRes;
		s_stageIspec.bins.length = maxFreq + 1;
		// prevent further TLS guard overhead
		IntensitySpectrum stageIspec = s_stageIspec;
		// first we fill cutoff bins with zeroes
		for (int i = 0; i < minFreq; i++)
			stageIspec.bins[i] = 0.0f;
		stageIspec.bins[$-1] = 0.0f;
		float range = (listenerPos - m_transform.wposition).length;
		float relBearing = courseAngle(listenerPos - m_transform.wposition) - m_transform.wrotation;
		// now actual power calculation
		float freqCubeStart = pow(m_shaftFreqStart, 3);
		assert(!isNaN(freqCubeStart));
		float freqCubeEnd = pow(m_shaftFreqEnd, 3);
		assert(!isNaN(freqCubeEnd));
		bool cavitation = fabs(m_normalVelStart) > m_critNormalVel;
		float cavSqrStart = cavitation ?
			(m_normalVelStart - m_critNormalVel) * fabs(m_normalVelStart - m_critNormalVel) :
			0.0f;
		cavitation = fabs(m_normalVelEnd) > m_critNormalVel;
		float cavSqrEnd = cavitation ?
			(m_normalVelEnd - m_critNormalVel) * fabs(m_normalVelEnd - m_critNormalVel) :
			0.0f;
		// prepare common modulators
		ThrachioidModulator tm;
		if (needTds)
		{
			tm = new ThrachioidModulator(m_tm);
			tm.startFundFreq = m_shaftFreqStart;
			tm.endFundFreq = m_shaftFreqEnd;
		}
		// broadband
		genISpec(range, relBearing, stageIspec, m_baseBBSpectrum, minFreq, maxFreq,
			freqCubeStart, freqCubeEnd, dissMod);
		float bandSum = stageIspec.bins[minFreq - 1 .. $].sum() / (maxFreq + 1);
		onSignalReady(bandSum, needTds ?
			genTds(stageIspec, genChainModulator(freqCubeStart, freqCubeEnd, tm)) :
			TimeDomainSignal.init);
		// cavitation
		genISpec(range, relBearing, stageIspec, m_baseCavSpectrum, minFreq, maxFreq,
			cavSqrStart, cavSqrEnd, dissMod);
		bandSum = stageIspec.bins[minFreq - 1 .. $].sum() / (maxFreq + 1);
		onSignalReady(bandSum, needTds ?
			genTds(stageIspec, genChainModulator(cavSqrStart, cavSqrEnd, tm)) :
			TimeDomainSignal.init);
	}
}


version (unittest)
{

	PropellerSoundPrototype stdPropellerProto()
	{
		PropellerSoundPrototype tmpl;
		auto ilspec = loadSpectrumFromImage("std_propeller.png", 80.0f, 140.0f);
		ilspec.addNumericNoise(0.5f);
		tmpl.baseBBSpectrum = ilspec.toIntensity;
		assert(tmpl.baseBBSpectrum.bins.length == 2049);
		ilspec = loadSpectrumFromImage("std_propeller_cav.png", 60.0f, 140.0f);
		ilspec.addNumericNoise(0.5f);
		tmpl.baseCavSpectrum = ilspec.toIntensity;
		assert(tmpl.baseCavSpectrum.bins.length == 2049);
		//tmpl.am = AmplitudeModulatorParams(
		//	[0.01f, 0.01f, 0.005f, 0.001f, 0.6f, 0.0001f], 0.0f);
		tmpl.tm = ThrachioidModulatorParams([0.2f, 0.05f, 0.01f, 0.001f, 0.8f, 0.001f],
			0.5, 0.7, -0.4);
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
	import std.stdio;

	PropellerSound ps = new PropellerSound(new Transform2D(), PropellerSoundPrototype());
	ps.m_bladeRadius = 4.2f;
	ps.m_bladeAoA = dgr2rad(30.0);
	ps.preUpdate(2.0f, 0.0f);
	writeln("2Hz propeller normalVel on 0 m/s: ", ps.m_normalVelStart);
	ps.preUpdate(2.0f, 5.0f);
	writeln("2Hz propeller normalVel on 5 m/s: ", ps.m_normalVelStart);
	ps.preUpdate(2.0f, 15.0f);
	writeln("2Hz propeller normalVel on 15 m/s: ", ps.m_normalVelStart);
}