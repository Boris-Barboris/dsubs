module dsubs_sound.spectrum;

import dsubs_sound.common;
import dsubs_sound.wav;


/// Represents spectrum of a periodic signal
struct Spectrum
{
	Complex!float[] bins;

	/// frequency resolution: Hz / bin
	int freqRes;

	void toTimeDomain(Fft fftCache, ref TimeDomainSignal dest) const
	{
		dest.sampleRate = bins.length.to!int * freqRes;
		fftCache.inverseFft(bins, dest.samples);
	}
}

float randPhase()
{
	return uniform(float(-PI), float(PI));
}

struct TimeDomainSignal
{
	Complex!float[] samples;
	int sampleRate;
}

Spectrum whiteNoise(int bins = 4096, int freqRes = 1)
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

// correctness test
unittest
{
	import std.stdio;

	Spectrum s = whiteNoise();
	writeln("ifft test bins: ", s.bins[0 .. 8], s.bins[4088 .. 4096]);
	Fft fftCache = new Fft(4096);
	TimeDomainSignal tds;
	tds.samples.length = 4096;
	s.toTimeDomain(fftCache, tds);
	assert(!isNaN(tds.samples[0].re));
	assert(!isNaN(tds.samples[0].im));
	writeln("ifft test tds: ", tds.samples[0 .. 8], tds.samples[4088 .. 4096]);
	writeln("ifft test tds sample rate: ", tds.sampleRate);
	writeWavFile("ifft_test.wav", tds.samples, 1 / 16.0f, tds.sampleRate);
}

// ifft benchmark
void runIfftBenchmark()
{
	import core.time;
	import std.stdio;

	Spectrum s = whiteNoise(4096);
	Fft fftCache = new Fft(4096);
	TimeDomainSignal tds;
	tds.samples.length = 4096;

	writeln("starting ifft benchmark");
	auto start = MonoTime.currTime();
	for (int i = 0; i < 4000; i++)
		s.toTimeDomain(fftCache, tds);
	auto end = MonoTime.currTime;
	writeln("1 ifft takes ", (end - start) / 4000);
}