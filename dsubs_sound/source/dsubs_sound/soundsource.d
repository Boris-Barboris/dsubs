module dsubs_sound.soundsource;

import dsubs_sound.common;
import dsubs_sound.spectrum;
import dsubs_sound.water;
import dsubs_sound.modulation;


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
	@property const(AmplitudeModulator) modulator() const;

	/// Generate intensity spectrum towards relative bearing.
	void getIntensitySpectrum(vec2d listenerPos, ref IntensitySpectrum dest,
		int minFreq, int maxFreq, float dissMod) const;
}


final class PropellerSound: SoundSource
{
	this(Transform2D t)
	{
		super(t);
	}

	private
	{
		// Base reference intensity spectrum of non-cavitating component on 1Hz
		IntensitySpectrum m_baseBBSpectrum;
		// Base reference intensity spectrum of cavitation noise component on criticalNormalVel
		IntensitySpectrum m_baseCavSpectrum;

		AmplitudeModulator m_modulator;
		float m_bladeRadius;
		float m_bladeAoA;
		float m_rotFreq;
		float m_normalVel;

		// cavitation starts at this water normal velocity
		float m_critNormalVel;
		float m_CavSquareK;
		float m_rngSpan;
	}

	override @property float radius() const { return 2.0f * m_bladeRadius; }

	override @property bool isModulated() const { return true; }

	override @property const(AmplitudeModulator) modulator() const { return m_modulator; }

	/// Update state at the beginning of kinematic simulation. rotFreq is shaft rotation
	/// frequency. waterSpeed is projection of water relative speed on shaft axis.
	void preUpdate(float rotFreq, float waterSpeed)
	{
		m_rotFreq = m_modulator.startFundFreq = rotFreq;
		// linear blade edge velocity
		vec2f bladeVel = vec2f(0.0f, -m_rotFreq * 2 * PI * m_bladeRadius);
		vec2f waterVel = bladeVel + vec2f(waterSpeed, 0.0f);
		vec2f bladeNormal = vec2f(-cos(m_bladeAoA), -sin(m_bladeAoA));
		m_normalVel = fabs(dot(bladeNormal, waterVel));
	}

	/// Modulator needs to know final rotation speed to simulate a smooth transition.
	void postUpdate(float rotFreq)
	{
		m_modulator.endFundFreq = rotFreq;
	}

	override void getIntensitySpectrum(vec2d listenerPos, ref IntensitySpectrum dest,
		int minFreq, int maxFreq, float dissMod) const
	{
		float range = listenerPos.length;
		dest.freqRes = m_baseBBSpectrum.freqRes;
		dest.bins.length = maxFreq;
		// Broadband component
		if (m_rotFreq != 0.0f)
		{
			float bbGain = 2.0f * toDb(m_rotFreq);
		}
	}
}

unittest
{
	import std.stdio;

	PropellerSound ps = new PropellerSound(new Transform2D());
	ps.m_bladeRadius = 4.2f;
	ps.m_bladeAoA = dgr2rad(30.0);
	ps.preUpdate(2.0f, 0.0f);
	writeln("2Hz propeller normalVel on 0 m/s: ", ps.m_normalVel);
	ps.preUpdate(2.0f, 5.0f);
	writeln("2Hz propeller normalVel on 5 m/s: ", ps.m_normalVel);
	ps.preUpdate(2.0f, 15.0f);
	writeln("2Hz propeller normalVel on 15 m/s: ", ps.m_normalVel);
}