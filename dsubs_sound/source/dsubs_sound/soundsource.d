module dsubs_sound.soundsource;

import dsubs_sound.common;
import dsubs_sound.spectrum;
import dsubs_sound.water;
import dsubs_sound.modulation;
import dsubs_sound.image;


/// Anisotropic sound emitter
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

	/// Generate intensity spectrum towards relative bearing. Returns modulator
	/// that should be used to transform the spectrum to time-domain signal.
	IModulator getIntensitySpectrum(vec2d listenerPos, ref IntensitySpectrum dest,
		int minFreq, int maxFreq, bool needModulator, float dissMod = 1.0f) const;
}


struct PropellerSoundPrototype
{
	IntensitySpectrum baseBBSpectrum;
	IntensitySpectrum baseCavSpectrum;
	AmplitudeModulatorParams am;
	float bladeRadius;
	float bladeAoA;
	float critNormalVel;
	float rngSpan = 0.0f;
}


final class PropellerSound: SoundSource
{
	this(Transform2D t, PropellerSoundPrototype templ)
	{
		super(t);
		m_baseBBSpectrum = templ.baseBBSpectrum;
		m_baseCavSpectrum = templ.baseCavSpectrum;
		m_am = templ.am;
		m_bladeRadius = templ.bladeRadius;
		m_bladeAoA = templ.bladeAoA;
		m_critNormalVel = templ.critNormalVel;
		m_rngSpan = templ.rngSpan;
	}

	private
	{
		// Base reference intensity spectrum of non-cavitating component on 1Hz
		IntensitySpectrum m_baseBBSpectrum;
		// Base reference intensity spectrum of cavitation noise component on
		// criticalNormalVel + 1m/s
		IntensitySpectrum m_baseCavSpectrum;

		AmplitudeModulatorParams m_am;
		float m_bladeRadius;
		float m_bladeAoA;
		float m_shaftFreqStart, m_shaftFreqEnd;
		float m_normalVelStart, m_normalVelEnd;

		// cavitation starts at this water normal velocity
		float m_critNormalVel;
		float m_rngSpan;
	}

	override @property float radius() const { return 2.0f * m_bladeRadius; }

	override @property const(IModulator) modulator() const { return m_modulator; }

	/// Update state at the beginning of kinematic simulation. rotFreq is shaft rotation
	/// frequency. waterSpeedStart is projection of water relative speed on shaft axis.
	void preUpdate(float shaftFreqStart, float waterSpeedStart)
	{
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
		m_shaftFreqStart = endShaftFreq;
		m_normalVelEnd = caclNormalVel(endShaftFreq, waterSpeedEnd);
		m_am.updatePhase(dt, endShaftFreq);
	}

	override IModulator getIntensitySpectrum(vec2d listenerPos, ref IntensitySpectrum dest,
		int minFreq, int maxFreq, bool needModulator, float dissMod = 1.0f) const
	{
		assert(m_baseBBSpectrum.bins.length == m_baseCavSpectrum.bins.length);
		assert(m_baseBBSpectrum.freqRes == m_baseCavSpectrum.freqRes);
		dest.freqRes = m_baseBBSpectrum.freqRes;
		dest.bins.length = maxFreq;
		// first we fill cutoff bins with zeroes
		for (int i = 0; i < minFreq - 1; i++)
			dest.bins[i] = 0.0f;
		// now actual power calculation;
		float avgFreq = (m_am.startFundFreq + m_am.endFundFreq) / 2;
		float freqCube = pow(avgFreq, 3);
		float avgNormalVel = (m_normalVelStart + m_normalVelEnd) / 2;
		bool cavitation = fabs(avgNormalVel) > m_critNormalVel;
		float cavSqr = cavitation ? pow(avgNormalVel - m_critNormalVel, 2) : 0.0f;
		float range = (listenerPos - m_transform.wposition).length;
		float totalBB = 0.0f;
		float totalCav = 0.0f;
		for (int i = minFreq - 1; i < maxFreq; i++)
		{
			float output = m_baseBBSpectrum.bins[i] * freqCube;
			totalBB += output;
			if (cavitation)
			{
				float cav = m_baseCavSpectrum.bins[i] * cavSqr;
				output += cav;
				totalCav += cav;
			}
			// apply linear-space randomization
			output += output * uniform(-m_rngSpan, m_rngSpan);
			// now we apply water sound loss
			IntensityLevel outputDb = IntensityLevel(output.toDb());
			outputDb = getILatRange(i + 1, outputDb, range, dissMod);
			dest.bins[i] = outputDb.toLinear();
		}
		// calculate approximation for Intensity interpolator
		float edgeFreqCube = pow(m_am.startFundFreq, 3);
		cavitation = fabs(m_normalVelStart) > m_critNormalVel;
		float edgeCavSqr = cavitation ? pow(m_normalVelStart - m_critNormalVel, 2) : 0.0f;
		m_iinterp.startIntensityMult =
			(edgeFreqCube * totalBB + edgeCavSqr * totalCav) /
			(freqCube * totalBB + cavSqr * totalCav);
		edgeFreqCube = pow(m_am.endFundFreq, 3);
		cavitation = fabs(m_normalVelEnd) > m_critNormalVel;
		edgeCavSqr = cavitation ? pow(m_normalVelEnd - m_critNormalVel, 2) : 0.0f;
		m_iinterp.endIntensityMult =
			(edgeFreqCube * totalBB + edgeCavSqr * totalCav) /
			(freqCube * totalBB + cavSqr * totalCav);
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
		tmpl.am = AmplitudeModulatorParams(
			[0.2f, 0.01f, 0.007f, 0.009f, 0.18f, 0.006f], 0.0f);
		tmpl.bladeRadius = 4.2f;
		tmpl.bladeAoA = dgr2rad(30.0);
		tmpl.critNormalVel = 8.0f;
		tmpl.rngSpan = 0.03f;
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