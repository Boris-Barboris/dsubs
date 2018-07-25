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

	/// Is sound amplitude-modulated?
	@property bool isModulated() const;

	/// get modulator
	@property ref const(AmplitudeModulator) modulator() const;

	/// Generate intensity spectrum towards relative bearing.
	void getIntensitySpectrum(vec2d listenerPos, ref IntensitySpectrum dest,
		int minFreq, int maxFreq, float dissMod = 1.0f);
}


struct PropellerSoundPrototype
{
	IntensitySpectrum baseBBSpectrum;
	IntensitySpectrum baseCavSpectrum;
	AmplitudeModulator modulator;
	float bladeRadius;
	float bladeAoA;
	float critNormalVel;
	float rngSpan;
}


final class PropellerSound: SoundSource
{
	this(Transform2D t, PropellerSoundPrototype templ)
	{
		super(t);
		m_baseBBSpectrum = templ.baseBBSpectrum;
		m_baseCavSpectrum = templ.baseCavSpectrum;
		m_modulator = templ.modulator;
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

		AmplitudeModulator m_modulator;
		float m_bladeRadius;
		float m_bladeAoA;
		float m_rotFreq;
		float m_normalVel;

		// cavitation starts at this water normal velocity
		float m_critNormalVel;
		float m_rngSpan;
	}

	@property float normalVel() const { return m_normalVel; }

	override @property float radius() const { return 2.0f * m_bladeRadius; }

	override @property bool isModulated() const { return true; }

	override @property ref const(AmplitudeModulator) modulator() const { return m_modulator; }

	/// Update state at the beginning of kinematic simulation. rotFreq is shaft rotation
	/// frequency. waterSpeed is projection of water relative speed on shaft axis.
	void preUpdate(float startShaftFreq, float waterSpeed)
	{
		m_rotFreq = m_modulator.startFundFreq = startShaftFreq;
		// linear blade edge velocity
		vec2f bladeVel = vec2f(0.0f, -m_rotFreq * 2 * PI * m_bladeRadius);
		vec2f waterVel = bladeVel + vec2f(waterSpeed, 0.0f);
		vec2f bladeNormal = vec2f(-cos(m_bladeAoA), -sin(m_bladeAoA));
		m_normalVel = fabs(dot(bladeNormal, waterVel));
	}

	/// Modulator needs to know final rotation speed to simulate a smooth transition.
	void postUpdate(float endShaftFreq, float dt)
	{
		m_modulator.endFundFreq = endShaftFreq;
		m_modulator.updatePhase(dt);
	}

	override void getIntensitySpectrum(vec2d listenerPos, ref IntensitySpectrum dest,
		int minFreq, int maxFreq, float dissMod = 1.0f)
	{
		assert(m_baseBBSpectrum.bins.length == m_baseCavSpectrum.bins.length);
		assert(m_baseBBSpectrum.freqRes == m_baseCavSpectrum.freqRes);
		dest.freqRes = m_baseBBSpectrum.freqRes;
		dest.bins.length = maxFreq;
		// first we fill cutoff bins with zeroes
		for (int i = 0; i < minFreq - 1; i++)
			dest.bins[i] = 0.0f;
		// now actual power calculation;
		float freqCube = pow(m_rotFreq, 3);
		bool cavitation = fabs(m_normalVel) > m_critNormalVel;
		float cavSqr = 0.0f;
		if (cavitation)
			cavSqr = pow(m_normalVel - m_critNormalVel, 2);
		float range = (listenerPos - m_transform.wposition).length;
		for (int i = minFreq - 1; i < maxFreq; i++)
		{
			float output = m_baseBBSpectrum.bins[i] * freqCube;
			if (cavitation)
				output += m_baseCavSpectrum.bins[i] * cavSqr;
			// apply linear-space randomization
			output += output * m_rngSpan * uniform01!float();
			// now we apply water sound loss
			IntensityLevel outputDb = IntensityLevel(output.toDb());
			outputDb = getILatRange(i + 1, outputDb, range, dissMod);
			dest.bins[i] = outputDb.toLinear();
		}
	}
}

PropellerSoundPrototype stdPropellerProto()
{
	PropellerSoundPrototype tmpl;
	auto ilspec = loadSpectrumFromImage("std_propeller.png");
	ilspec.addNumericNoise(0.5f);
	tmpl.baseBBSpectrum = ilspec.toIntensity;
	ilspec = loadSpectrumFromImage("std_propeller_cav.png");
	ilspec.addNumericNoise(0.5f);
	tmpl.baseCavSpectrum = ilspec.toIntensity;
	tmpl.modulator = AmplitudeModulator(0.0f, 0.0f,
		[0.2f, 0.01f, 0.007f, 0.009f, 0.18f, 0.006f], 0.0f);
	tmpl.bladeRadius = 4.2f;
	tmpl.bladeAoA = dgr2rad(30.0);
	tmpl.critNormalVel = 8.0f;
	tmpl.rngSpan = 0.03f;
	return tmpl;
}


unittest
{
	import std.stdio;

	PropellerSound ps = new PropellerSound(new Transform2D(), PropellerSoundPrototype());
	ps.m_bladeRadius = 4.2f;
	ps.m_bladeAoA = dgr2rad(30.0);
	ps.preUpdate(2.0f, 0.0f);
	writeln("2Hz propeller normalVel on 0 m/s: ", ps.m_normalVel);
	ps.preUpdate(2.0f, 5.0f);
	writeln("2Hz propeller normalVel on 5 m/s: ", ps.m_normalVel);
	ps.preUpdate(2.0f, 15.0f);
	writeln("2Hz propeller normalVel on 15 m/s: ", ps.m_normalVel);
}