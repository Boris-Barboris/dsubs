module dsubs_sound.modulation;

import dsubs_sound.common;
import dsubs_sound.spectrum;


/// DEMON component that modulates time-domain signal with a cascade of harmonics
struct AmplitudeModulator
{
	float fundFreq;		/// fundamental frequency
	float[] harmonics;	/// [fundFreq, 2 * fundFreq, 3 * fundFreq ...] amplitudes
	float startPhase;

	void modulate(ref TimeDomainSignal dest)
	{
		import std.algorithm.iteration: map, sum;

		assert(harmonics.length > 0);
		float dt = 1.0f / dest.samplingRate;
		static float[] phases;
		phases.length = harmonics.length;
		float DC = sqrt(1.0 - 0.5 * sum(harmonics.map!(a => a * a)));
		assert(!isNaN(DC));
		// main modulation loop
		for (size_t i = 0; i < dest.samples.length; i++)
		{
			float phaseCommon = dt * i * 2 * PI * fundFreq;
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
	AmplitudeModulator am = AmplitudeModulator(2.5f, [0.2f, 0.01f, 0.25f, 0.01f, 0.06f, 0.03f], 0.0f);
	am.modulate(tds);
	writeWavFile("am_test.wav", tds.samples, 1.0f, tds.samplingRate);
}