module dsubs_sound.soundsource;

import dsubs_sound.common;
import dsubs_sound.spectrum;
import dsubs_sound.modulation;


/// Positioned sound signal emitter
class SoundSource
{
	this(Transform2D t)
	{
		m_transform = t;
	}

	protected
	{
		Transform2D m_transform;
		IntensitySpectrum m_ispec;
		AmplitudeModulator m_modulator;
		bool am;	// amplitude modulation
	}

	/// Physical radius of emitting area. Affects tha halo size on
	/// close distances.
	float radius = 1.0f;

	final @property Transform2D transform() { return m_transform; }

	@property void modulator(AmplitudeModulator rhs)
	{
		am = true;
		m_modulator = rhs;
	}

	/// set reference intensity spectrum
	@property void ispec(AmplitudeModulator rhs)
	{
		am = true;
		m_modulator = rhs;
	}

	/// global gain that is added to intensity
	dB gain = 0.0f;
}