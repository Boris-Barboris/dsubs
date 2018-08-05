module dsubs_sound.modulation;

import dsubs_sound.common;
import dsubs_sound.spectrum;


interface IModulator
{
	void modulate(ref TimeDomainSignal dest) const;
}


final class ChainModulator: IModulator
{
	IModulator[] modulators;

	this(IModulator[] mods)
	{
		modulators = mods;
	}

	void modulate(ref TimeDomainSignal dest) const
	{
		foreach (m; modulators)
			m.modulate(dest);
	}
}

/// Linearly interpolates intensity of the signal
final class IntensityInterpolator: IModulator
{
	float startIntensityMult = 1.0f;
	float endIntensityMult = 1.0f;

	void modulate(ref TimeDomainSignal dest) const
	{
		assert(dest.samples.length > 1);
		float mult = startIntensityMult;
		float di = (endIntensityMult - startIntensityMult) / (dest.samples.length - 1);
		for (size_t i = 0; i < dest.samples.length; i++)
		{
			dest.samples[i].re *= sqrt(mult.abs);
			mult += di;
		}
	}
}

struct AmplitudeModulatorParams
{
	/// [fundFreq, 2 * fundFreq, 3 * fundFreq ...] amplitudes
	immutable(float)[] harmonics;
	float startPhase = 0.0f;

	/// move phase forward according to freq
	void updatePhase(float time, float freq)
	{
		startPhase += time * 2 * PI * freq;
		startPhase = fmod(startPhase, 2 * PI);
	}
}

// DEMON - detection of envelope modulation on noise

/// Sine harmonics cascade modulator, useful for shaft and blade pass
/// frequency modulation.
final class AmplitudeModulator: IModulator
{
	this(AmplitudeModulatorParams params)
	{
		harmonics = params.harmonics;
		startPhase = params.startPhase;
	}

	float startFundFreq = 0.0f;	/// fundamental frequency at the beginning
	float endFundFreq = 0.0f;	/// fundamental frequency at the end

	private immutable(float)[] harmonics;
	private float startPhase = 0.0f;

	/// modulate time-domain signal
	void modulate(ref TimeDomainSignal dest) const
	{
		import std.algorithm.iteration: map, sum;

		assert(harmonics.length > 0);
		assert(dest.samples.length > 0);
		float dt = 1.0f / dest.samplingRate;
		assert(!isNaN(dt));
		static float[] s_phases;
		s_phases.length = harmonics.length;
		float[] phases = s_phases;	// optimize out TLS access
		float DC = sqrt(1.0f - 0.5f * sum(harmonics.map!(a => a * a)));
		assert(!isNaN(DC));
		// main modulation loop
		float dfreq = (endFundFreq - startFundFreq) / (dest.samples.length - 1);
		for (size_t i = 0; i < dest.samples.length; i++)
		{
			float freq = startFundFreq + dfreq * i;
			float phaseCommon = dt * i * 2 * PI * freq;
			for (size_t j = 0; j < harmonics.length; j++)
				phases[j] = (startPhase + phaseCommon) * (j + 1);
			float modk = DC;
			for (size_t j = 0; j < harmonics.length; j++)
				modk += harmonics[j] * sin(phases[j]);
			dest.samples[i].re *= modk;
		}
	}
}


/// 1.0 + A * sin(x + PI_2 + B * sin(x) + C)
struct ThrachioidModulatorParams
{
	private
	{
		float A = 0.0f;
		float B = 0.0f;
		float C = 0.0f;
		float startPhase = 0.0f;
		immutable(float)[] harmonics;

		float energyIntegral = 1.0f;
	}

	this(immutable(float)[] harmonics,
		float A, float B, float C, float startPhase = 0.0f)
	{
		this.harmonics = harmonics;
		this.A = A;
		this.B = B;
		this.C = C;
		this.startPhase = startPhase;
		calculateIntegral(40);
	}

	private float get(float x) const
	{
		return A * sin(x + PI_2 + B * sin(x) + C);
	}

	private void calculateIntegral(int resolution = 40)
	{
		energyIntegral = 0.0f;
		float dt = PI * 2 / resolution;
		for (int i = 0; i < resolution; i++)
		{
			float val = 1.0f;
			for (int j = 0; j < harmonics.length; j++)
			{
				float phase = dt * i * (j + 1);
				val += harmonics[j] * get(phase);
			}
			assert(val >= 0.0f);
			energyIntegral += pow(val, 2);
		}
		energyIntegral /= resolution;
		assert(energyIntegral > 0.0f, "non-positive energy for modulator");
	}

	/// move phase forward according to freq
	void updateStartPhase(float time, float freq)
	{
		startPhase += time * 2 * PI * freq;
		startPhase = fmod(startPhase, 2 * PI);
	}
}


final class ThrachioidModulator: IModulator
{
	this(ThrachioidModulatorParams params)
	{
		this.params = params;
	}

	float startFundFreq = 0.0f;
	float endFundFreq = 0.0f;

	private ThrachioidModulatorParams params;

	/// modulate time-domain signal
	void modulate(ref TimeDomainSignal dest) const
	{
		assert(dest.samples.length > 0);
		float dt = 1.0f / dest.samplingRate;
		assert(!isNaN(dt));
		float linGain = 1.0f / sqrt(params.energyIntegral);
		assert(!isNaN(linGain));

		// main modulation loop
		float dfreq = (endFundFreq - startFundFreq) / (dest.samples.length - 1);
		for (size_t i = 0; i < dest.samples.length; i++)
		{
			float freq = startFundFreq + dfreq * i;
			float phaseCommon = dt * i * 2 * PI * freq;
			float modk = 1.0f;
			for (size_t j = 0; j < params.harmonics.length; j++)
			{
				float phase = (params.startPhase + phaseCommon) * (j + 1);
				modk += params.harmonics[j] * params.get(phase);
			}
			dest.samples[i].re *= modk * linGain;
		}
	}
}

// correctness test
unittest
{
	import dsubs_sound.wav;

	Fft fftCache = new Fft(4096);
	TimeDomainSignal tds = whiteNoise(4096 * 4, 4096);
	AmplitudeModulator am = new AmplitudeModulator(
		AmplitudeModulatorParams([0.2f, 0.01f, 0.25f, 0.01f, 0.06f], 0.0f));
	am.startFundFreq = 0.5f;
	am.endFundFreq = 2.0f;
	am.modulate(tds);
	writeWavFile("am_test.wav", tds.samples, 1.0f, tds.samplingRate);
}