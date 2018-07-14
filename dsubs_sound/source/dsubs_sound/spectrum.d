module dsubs_sound.spectrum;

import dsubs_sound.common;
import dsubs_sound.wav;


/// Right half of spectrum. If desired spectrum size is 4096, this must be 4096 / 2 - 1.
struct IntensityLevelSpectrum
{
	// first bin is 1Hz
	IntensityLevel[] bins;
	int freqRes = 1;	/// frequency resolution (Hz / bin)

	/// convert intensity level spectrum to pressure spectrum using rng to
	/// create random phases.
	void genSpectrum(ref Spectrum dest) const
	{
		assert((bins.length + 1) % 2 == 0);
		dest.freqRes = freqRes;
		dest.bins.length = bins.length * 2 + 2;
		for (size_t i = 0; i < bins.length; i++)
		{
			dest.bins[i + 1] = fromPolar((bins[i] / 2).toLinear, randPhase());
			dest.bins[$ - 1 - i] = dest.bins[i + 1].conj;
		}
		dest.bins[0] = dest.bins[$/2] = complex!float(0);
	}
}

/// Right half of spectrum. If desired spectrum size is 4096, this must be 4096 / 2 - 1.
struct IntensitySpectrum
{
	// first bin is 1Hz
	Intensity[] bins;
	int freqRes = 1;	/// frequency resolution (Hz / bin)

	/// convert intensity spectrum to pressure spectrum using rng to
	/// create random phases.
	void genSpectrum(ref Spectrum dest) const
	{
		assert((bins.length + 1) % 2 == 0);
		dest.freqRes = freqRes;
		dest.bins.length = bins.length * 2 + 2;
		for (size_t i = 0; i < bins.length; i++)
		{
			dest.bins[i + 1] = fromPolar(sqrt(bins[i]), randPhase());
			dest.bins[$ - 1 - i] = dest.bins[i + 1].conj;
		}
		dest.bins[0] = dest.bins[$/2] = complex!float(0);
	}
}


unittest
{
	import std.algorithm;
	import std.stdio;
	import dsubs_sound.wav;

	IntensityLevelSpectrum ispec;
	ispec.bins.length = 2047;
	ispec.bins.each!((ref IntensityLevel il) => il.val = 82.0f - 4 * uniform01!float);
	Spectrum pspec;
	ispec.genSpectrum(pspec);
	assert(pspec.bins.length == 4096);
	Fft fftCache = new Fft(4096);
	TimeDomainSignal tds;
	pspec.toTimeDomain(fftCache, tds);
	float maxp = tds.samples.map!(a => a.re).maxElement;
	writeln("IntensityLevelSpectrum test result: ", tds.samples[0 .. 6],
		", max pressure: ", maxp);
	writeWavFile("ispec_whitenoise.wav", tds.samples, 0.5f / maxp, tds.samplingRate);
}

/// Amplitude spectrum of a periodic signal, ready for IFFT
struct Spectrum
{
	Complex!float[] bins;
	int freqRes = 1;	/// frequency resolution (Hz / bin)

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

/// Create smooth transition from prev to onto. onto samples will be changed.
/// Function tries to make power transition smooth.
void overlapTDS(const TimeDomainSignal prev, TimeDomainSignal onto, int sampleCount)
{
	assert(prev.samplingRate == onto.samplingRate);
	for (int i = 0; i < sampleCount; i++)
	{
		// power factor
		float factor = float(i + 1) / (sampleCount + 1);
		onto.samples[i].re = onto.samples[i].re * sqrt(factor) +
			sqrt(1.0f - factor) * prev.samples[$ - sampleCount + i].re;
	}
}

unittest
{
	import std.range;

	auto tds1 = whiteNoise(4096, 4096);
	auto tds2 = whiteNoise(4096, 4096);
	overlapTDS(tds1, tds2, 256);
	writeWavFile("overlap.wav", chain(tds1.samples, tds2.samples), 1.0f, tds1.samplingRate);
}

Spectrum whiteNoiseSpectrum(int bins = 4096, int freqRes = 1)
{
	Spectrum s;
	s.freqRes = freqRes;
	s.bins.length = bins;
	for (int i = 1; i < bins / 2; i++)
	{
		s.bins[i] = fromPolar(1.25f - 0.5f * uniform01!float(), randPhase());
		s.bins[$ - i] = s.bins[i].conj;
	}
	s.bins[0] = s.bins[$/2] = complex!float(0);
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
	import std.algorithm.iteration;
	import std.stdio;
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