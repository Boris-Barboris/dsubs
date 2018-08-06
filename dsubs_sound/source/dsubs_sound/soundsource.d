module dsubs_sound.soundsource;

import dsubs_common.event;

import dsubs_sound.common;
import dsubs_sound.spectrum;
import dsubs_sound.water;
import dsubs_sound.modulation;
import dsubs_sound.image;


abstract class SoundSource
{
	this(Transform2D t)
	{
		m_transform = t;
	}

	private Transform2D m_transform;

	final @property Transform2D transform() { return m_transform; }

	/// Physical radius of emitting area. Affects tha halo size on
	/// close distances.
	@property float radius() const;

	/// invoked by simulator before kinematic update happens
	Event!(void delegate()) onPreSimulation;
	/// invoked by simulator right after kinematic update happens
	Event!(void delegate(float dt)) onPostSimulation;

	/// Generate intensity spectrum towards relative bearing.
	void getIntensitySpectrum(vec2d listenerPos, ref IntensitySpectrum dest,
		void delegate(const(IModulator) mod) onSpectrumBuilt, int minFreq, int maxFreq,
		bool needModulator, float dissMod = 1.0f) const;
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
		super(t);
		m_baseBBSpectrum = p.baseBBSpectrum;
		m_baseCavSpectrum = p.baseCavSpectrum;
		//m_am = templ.am;
		m_tm = p.tm;
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

	override @property float radius() const { return 2.0f * m_bladeRadius; }

	/// Update state at the beginning of kinematic simulation. rotFreq is shaft rotation
	/// frequency. waterSpeedStart is projection of water relative speed on shaft axis.
	void preUpdate(float shaftFreqStart, float waterSpeedStart)
	{
		assert(!isNaN(shaftFreqStart));
		assert(!isNaN(waterSpeedStart));
		m_shaftFreqStart = shaftFreqStart;
		m_normalVelStart = caclNormalVel(shaftFreqStart, waterSpeedStart);
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
	}

	private void genISpec(float range, float relBearing, ref IntensitySpectrum dest,
		const IntensitySpectrum source, int minFreq, int maxFreq,
		float kstart, float kend, float dissMod = 1.0f) const
	{
		float kavg = (kstart.fabs + kend.fabs) / 2;
		float bearingK = 1.0f - 0.5f * (1.0f - m_aftIntensity) * (cos(2.0f * relBearing) + 1.0f);
		for (int i = minFreq - 1; i < maxFreq; i++)
		{
			float output = source.bins[i] * kavg;
			assert(!isNaN(output));
			// apply linear-space randomization
			output += output * uniform(-m_rngSpan, m_rngSpan);
			// apply bearing multiplier
			output *= bearingK;
			// now we apply water sound loss
			IntensityLevel outputDb = IntensityLevel(output.toDb());
			outputDb = getILatRange(i + 1, outputDb, range, dissMod);
			dest.bins[i] = outputDb.toLinear();
		}
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

	override void getIntensitySpectrum(vec2d listenerPos, ref IntensitySpectrum dest,
		void delegate(const(IModulator) mod) onSpectrumBuilt, int minFreq, int maxFreq,
		bool needModulator, float dissMod = 1.0f) const
	{
		assert(m_baseBBSpectrum.bins.length == m_baseCavSpectrum.bins.length);
		assert(m_baseBBSpectrum.freqRes == m_baseCavSpectrum.freqRes);
		dest.freqRes = m_baseBBSpectrum.freqRes;
		dest.bins.length = maxFreq;
		// first we fill cutoff bins with zeroes
		for (int i = 0; i < minFreq - 1; i++)
			dest.bins[i] = 0.0f;
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
		if (needModulator)
		{
			tm = new ThrachioidModulator(m_tm);
			tm.startFundFreq = m_shaftFreqStart;
			tm.endFundFreq = m_shaftFreqEnd;
		}
		// broadband
		genISpec(range, relBearing, dest, m_baseBBSpectrum, minFreq, maxFreq,
			freqCubeStart, freqCubeEnd, dissMod);
		onSpectrumBuilt(needModulator ?
			genChainModulator(freqCubeStart, freqCubeEnd, tm) : null);
		// cavitation
		// genISpec(range, dest, m_baseCavSpectrum, minFreq, maxFreq,
		// 	cavSqrStart, cavSqrEnd, dissMod);
		// onSpectrumBuilt(needModulator ?
		// 	genChainModulator(cavSqrStart, cavSqrEnd, am) : null);
	}
}


version (unittest)
{

	PropellerSoundPrototype stdPropellerProto()
	{
		PropellerSoundPrototype tmpl;
		auto ilspec = loadSpectrumFromImage("std_propeller.png");
		ilspec.addNumericNoise(0.5f);
		tmpl.baseBBSpectrum = ilspec.toIntensity;
		ilspec = loadSpectrumFromImage("std_propeller_cav.png");
		ilspec.addNumericNoise(0.5f);
		tmpl.baseCavSpectrum = ilspec.toIntensity;
		//tmpl.am = AmplitudeModulatorParams(
		//	[0.01f, 0.01f, 0.005f, 0.001f, 0.6f, 0.0001f], 0.0f);
		tmpl.tm = ThrachioidModulatorParams([0.2f, 0.05f, 0.01f, 0.001f, 0.8f, 0.001f],
			0.5, 0.7, -0.4);
		tmpl.bladeRadius = 4.2f;
		tmpl.bladeAoA = dgr2rad(30.0);
		tmpl.critNormalVel = 8.0f;
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