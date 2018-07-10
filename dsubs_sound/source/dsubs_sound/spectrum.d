module dsubs_sound.spectrum;

import dsubs_sound.common;


struct IntensitySpectrum
{
	IntensityLevel[] bins;
	int freqRes;	/// frequency resolution (Hz / bin)

	/// convert intensity spectrum to pressure spectrum using rng to
	/// create random phases.
	void genSpectrum(ref Spectrum dest) const
	{
		dest.freqRes = freqRes;
		dest.bins.length = bins.length;
		for (size_t i = 0; i < bins.length; i++)
			dest.bins[i] = fromPolar(bins[i].toLinear, randPhase());
	}
}

/// Frequency spectrum of a periodic signal
struct Spectrum
{
	Complex!float[] bins;
	int freqRes;	/// frequency resolution (Hz / bin)

	void toTimeDomain(Fft fftCache, ref TimeDomainSignal dest) const
	{
		dest.samplingRate = bins.length.to!int * freqRes;
		dest.samples.length = bins.length;
		fftCache.inverseFft(bins, dest.samples);
	}
}

/// generate random phase using thread-local RNG
float randPhase()
{
	return uniform(float(-PI), float(PI));
}

struct TimeDomainSignal
{
	Complex!float[] samples;
	int samplingRate;
}

Spectrum whiteNoiseSpectrum(int bins = 4096, int freqRes = 1)
{
	Spectrum s;
	s.freqRes = freqRes;
	s.bins.length = bins;
	for (int i = 1; i < bins / 2; i++)
	{
		s.bins[i] = fromPolar(uniform01!float(), randPhase());
		s.bins[bins - i] = complex(s.bins[i].re, -s.bins[i].im);
	}
	s.bins[0] = complex(0, 0);
	s.bins[bins / 2] = complex(0, 0);
	return s;
}

TimeDomainSignal whiteNoise(int sampleCount, int samplingRate, float level = 0.25f)
{
	TimeDomainSignal res;
	res.samplingRate = samplingRate;
	res.samples.length = sampleCount;
	for (size_t i = 0; i < sampleCount; i++)
		res.samples[i] = Complex!float(2 * level * (uniform01!float() - 0.5f), 0.0f);
	return res;
}

// correctness test
unittest
{
	import std.stdio;
	import dsubs_sound.wav;
	import std.algorithm.iteration;
	import std.range: repeat;

	Spectrum s = whiteNoiseSpectrum(4096, 1);
	Fft fftCache = new Fft(4096);
	TimeDomainSignal tds;
	s.toTimeDomain(fftCache, tds);
	assert(!isNaN(tds.samples[0].re));
	assert(!isNaN(tds.samples[0].im));
	writeln("ifft test tds sample rate: ", tds.samplingRate);
	writeWavFile("ifft_test_1bphz.wav", tds.samples.repeat(2).joiner(), 16.0f, tds.samplingRate);

	s = whiteNoiseSpectrum(2048, 2);
	s.toTimeDomain(fftCache, tds);
	writeWavFile("ifft_test_2bphz.wav", tds.samples.repeat(4).joiner(), 12.0f, tds.samplingRate);

	s = whiteNoiseSpectrum(1024, 4);
	s.toTimeDomain(fftCache, tds);
	writeWavFile("ifft_test_4bphz.wav", tds.samples.repeat(8).joiner(), 8.0f, tds.samplingRate);
}

void runIfftBenchmark()
{
	import core.time;
	import std.stdio;

	Spectrum s = whiteNoiseSpectrum(4096);
	Fft fftCache = new Fft(4096);
	TimeDomainSignal tds;
	tds.samples.length = 4096;

	writeln("starting ifft benchmark");
	auto start = MonoTime.currTime();
	for (int i = 0; i < 2000; i++)
		s.toTimeDomain(fftCache, tds);
	auto end = MonoTime.currTime;
	writeln("1 ifft takes ", (end - start) / 2000);
}