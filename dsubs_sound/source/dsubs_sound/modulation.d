module dsubs_sound.modulation;

import std.math;

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
		assert(startIntensityMult >= 0.0f);
		assert(endIntensityMult >= 0.0f);
		assert(dest.samples.length > 1);
		float mult = startIntensityMult;
		float di = (endIntensityMult - startIntensityMult) / (dest.samples.length - 1);
		for (size_t i = 0; i < dest.samples.length; i++)
		{
			dest.samples[i].re *= sqrt(mult);
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

/// DEMON component that modulates time-domain signal with a cascade of harmonics
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

	/// move phase forward according to endFundFreq
	void updatePhase(float time)
	{
		startPhase += time * 2 * PI * endFundFreq;
		startPhase = fmod(startPhase, 2 * PI);
	}

	/// modulate time-domain signal
	void modulate(ref TimeDomainSignal dest) const
	{
		import std.algorithm.iteration: map, sum;

		assert(harmonics.length > 0);
		float dt = 1.0f / dest.samplingRate;
		static float[] s_phases;
		s_phases.length = harmonics.length;
		float[] phases = s_phases;	// optimize out TLS access
		float DC = sqrt(1.0 - 0.5 * sum(harmonics.map!(a => a * a)));
		assert(!isNaN(DC));
		// main modulation loop
		float dfreq = (endFundFreq - startFundFreq) / dest.samples.length;
		for (size_t i = 0; i < dest.samples.length; i++)
		{
			float freq = startFundFreq + dfreq * i;
			float phaseCommon = dt * i * 2 * PI * freq;
			for (size_t j = 0; j < harmonics.length; j++)
				phases[j] = startPhase + phaseCommon * (j + 1);
			float modk = DC;
			for (size_t j = 0; j < harmonics.length; j++)
				modk += harmonics[j] * sin(phases[j]);
			dest.samples[i].re *= modk;
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