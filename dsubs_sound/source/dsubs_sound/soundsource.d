module dsubs_sound.soundsource;

import dsubs_sound.common;
import dsubs_sound.spectrum;
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
	void getIntensitySpectrum(double relBearing, ref IntensitySpectrum dest) const;
}


final class PropellerSound: SoundSource
{
	private
	{
		// Base reference intensity spectrum of non-cavitating component, per Hz
		IntensitySpectrum m_baseBBSpectrum;
		// Base reference intensity spectrum of cavitation noise component
		IntensitySpectrum m_baseCavSpectrum;

		AmplitudeModulator m_modulator;
		float m_bladeRadius;
		float m_bladeAoA;

		// cavitation starts at this water normal velocity
		float m_critNormalVel;
	}

	@property float radius() const { return 2.0f * m_bladeRadius; }

	@property bool isModulated() const { return true; }

	@property const(AmplitudeModulator) modulator() const { return m_modulator; }

	void getIntensitySpectrum(double relBearing, ref IntensitySpectrum dest) const
	{

	}
}