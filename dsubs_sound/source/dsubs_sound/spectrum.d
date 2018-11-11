module dsubs_sound.spectrum;

import core.time;
import std.stdio: writeln;
alias expi = std.complex.expi;

import dsubs_sound.common;
import dsubs_sound.wav;
import dsubs_sound.opencl;


/// OpenCL-backed intensity spectrum
final class IntensitySpectrumCl: Buffer
{
	this(DsubsSoundOpenclCtx ctx)
	{
		super(ctx, GLOBAL_SRATE * float.sizeof);
	}

	AsyncEvent startRead(ref float[GLOBAL_SRATE] dest,
		const (AsyncEvent)* onlyAfter = null)
	{
		return enqueueFullRead(&dest[0], onlyAfter);
	}

	void fullRead(ref float[GLOBAL_SRATE] dest, const (AsyncEvent)* onlyAfter = null)
	{
		super.fullRead(&dest[0], onlyAfter);
	}
}


private float[] g_phasesRandBuf;

/// Right half of spectrum.
struct IntensityLevelSpectrum
{
	// first bin is DC, last is nyquist
	IntensityLevel[] bins;
	int freqRes = 1;	/// frequency resolution (Hz / bin)

	/// convert intensity level spectrum to pressure spectrum using rng to
	/// create random phases.
	void genSpectrum(ref Spectrum dest) const
	{
		assert(bins.length % 2 == 1);
		dest.freqRes = freqRes;
		dest.bins.length = bins.length - 1;
		size_t N = dest.bins.length * 2;
		Complex!float j = Complex!float(0.0f, 1.0f);
		g_phasesRandBuf.length = bins.length;
		float[] phases = g_phasesRandBuf;
		for (size_t i = 0; i < phases.length; i++)
			phases[i] = randPhase();
		// read fftoptim.m octave file for demonstration
		// https://dsp.stackexchange.com/a/28712
		for (size_t k = 0; k < N / 2; k++)
		{
			float freqFactor = k > 0 ? 1.0f / k / freqRes : 0.0f;
			Complex!float Xk1 = fromPolar((bins[k] / 2).toLinear * freqFactor, phases[k]);
			size_t conjk = bins.length - 1 - k;
			freqFactor = conjk > 0 ? 1.0f / conjk / freqRes : 0.0f;
			Complex!float Xk2 = fromPolar((bins[conjk] / 2).toLinear * freqFactor,
				-phases[conjk]);
			Complex!float jw = j * expi(float(2) * PI * k / N);
			dest.bins[k] = 0.5f * (Xk1 * (1.0f + jw) + Xk2 * (1.0f - jw));
		}
	}

	IntensitySpectrum toIntensity() const
	{
		IntensitySpectrum res;
		res.freqRes = freqRes;
		res.bins.length = bins.length;
		foreach (i, ref b; res.bins)
			b = this.bins[i].toLinear;
		assert(res.bins.length % 2 == 1);
		return res;
	}

	void addNumericNoise(float amplitude)
	{
		// skip DC and nyquist
		for (size_t i = 1; i < bins.length - 1; i++)
			bins[i] = IntensityLevel(bins[i].val + uniform01!float * amplitude);
	}
}

/// Right half of spectrum.
struct IntensitySpectrum
{
	// first bin is DC, last is nyquist
	Intensity[] bins;
	int freqRes = 1;	/// frequency resolution (Hz / bin)

	/// convert intensity spectrum to pressure spectrum using rng to
	/// create random phases.
	void genSpectrum(ref Spectrum dest) const
	{
		assert(bins.length % 2 == 1, bins.length.to!string);
		dest.freqRes = freqRes;
		dest.bins.length = bins.length - 1;
		size_t N = dest.bins.length * 2;
		Complex!float j = Complex!float(0.0f, 1.0f);
		g_phasesRandBuf.length = bins.length;
		float[] phases = g_phasesRandBuf;
		for (size_t i = 0; i < phases.length; i++)
			phases[i] = randPhase();
		// read fftoptim.m octave file for demonstration
		// https://dsp.stackexchange.com/a/28712
		for (size_t k = 0; k < N / 2; k++)
		{
			float freqFactor = k > 0 ? 1.0f / k / freqRes : 0.0f;
			Complex!float Xk1 = fromPolar(sqrt(bins[k]) * freqFactor, phases[k]);
			size_t conjk = bins.length - 1 - k;
			freqFactor = conjk > 0 ? 1.0f / conjk / freqRes : 0.0f;
			Complex!float Xk2 = fromPolar(sqrt(bins[$ - 1 - k]) * freqFactor, -phases[conjk]);
			Complex!float jw = j * expi(float(2) * PI * k / N);
			dest.bins[k] = 0.5f * (Xk1 * (1.0f + jw) + Xk2 * (1.0f - jw));
		}
	}
}


/// Sliding TDS generator
struct SlidingGenerator
{
	private
	{
		float[] amplitudes;
		float[] phases;
		int minFreq;
		int nyqFreq;
		float dt;
	}

	this(float[] amplitudes, int minFreq = 1)
	{
		this.amplitudes = amplitudes;
		this.minFreq = minFreq;
		nyqFreq = minFreq + amplitudes.length.to!int;
		dt = 0.5f / nyqFreq;
		phases.length = amplitudes.length;
		for (int i = 0; i < amplitudes.length; i++)
			phases[i] = randPhase();
	}

	private float roll()
	{
		float res = 0.0f;
		float dphase = 2 * PI * dt;
		for (int f = minFreq, i = 0; f < nyqFreq; f++, i++)
		{
			phases[i] += f * dphase * uniform(0.95f, 1.05f);
			res += amplitudes[i] * sin(phases[i]);
		}
		return res;
	}

	void toTimeDomain(ref TimeDomainSignal dest, int sampleCount)
	{
		dest.samplingRate = nyqFreq * 2;
		dest.samples.length = sampleCount;
		for (size_t i = 0; i < sampleCount; i++)
			dest.samples[i] = roll();
	}
}

// unittest
// {
// 	import std.algorithm;
// 	import std.range;
// 	import std.stdio;
// 	import core.time;
// 	import dsubs_sound.wav;

// 	TimeDomainSignal tds;
// 	SlidingGenerator sgen = SlidingGenerator(1.0f.repeat(1548).array, 500);
// 	writeln("starting sliding generation, nyquist frequency: ", sgen.nyqFreq);
// 	auto start = MonoTime.currTime();
// 	sgen.toTimeDomain(tds, 4096 * 2);
// 	auto end = MonoTime.currTime();
// 	writeln("sliding generation took ", end - start);
// 	float maxp = tds.samples.map!(a => a.re).maxElement;
// 	writeWavFile("sliding_whitenoise.wav", tds.samples, 0.7f / maxp, tds.samplingRate);
// }


unittest
{
	import std.algorithm;
	import std.range;
	import std.stdio;
	import dsubs_sound.wav;

	IntensityLevelSpectrum ispec;
	ispec.bins.length = 2049;
	iota(1,2047).map!(i => ispec.bins[i].val = 82.0f - 4 * uniform01!float);
	Spectrum pspec;
	ispec.genSpectrum(pspec);
	assert(pspec.bins.length == 2048);
	Fft fftCache = new Fft(2048);
	TimeDomainSignal tds;
	pspec.toTimeDomain(fftCache, tds);
	assert(tds.samples.length == 4096);
	float maxp = tds.samples.maxElement;
	writeln("IntensityLevelSpectrum test result: ", tds.samples[0 .. 6],
		", max pressure: ", maxp);
	writeWavFile("ispec_whitenoise.wav", tds.samples, 0.5f / maxp, tds.samplingRate);
}

/// Amplitude (pressure) spectrum of a periodic signal, ready for IFFT
struct Spectrum
{
	Complex!float[] bins;
	int freqRes = 1;	/// frequency resolution (Hz / bin)

	void toTimeDomain(Fft fftCache, ref TimeDomainSignal dest) const
	{
		dest.samplingRate = bins.length.to!int * freqRes * 2;
		dest.samples.length = bins.length * 2;
		// auto beforeIfft = MonoTime.currTime;
		// smart trick with butterfly, consult octave fftoptim.m
		fftCache.inverseFft(bins, dest.reinterpret);
		// auto afterIfft = MonoTime.currTime;
		// writeln("ifft performed in ", afterIfft - beforeIfft);
	}
}

/// generate random phase using thread-local RNG
float randPhase()
{
	return uniform(float(-PI), float(PI));
}

struct TimeDomainSignal
{
	float[] samples;
	int samplingRate;

	pragma(inline)
	Complex!(float)[] reinterpret()
	{
		return (cast(Complex!(float)*) samples.ptr)[0 .. samples.length / 2];
	}

	void zeroOut(int sampleCount, int srate)
	{
		samplingRate = srate;
		samples.length = sampleCount;
		samples[] = 0.0f;
	}

	void copyTo(ref TimeDomainSignal dest) immutable
	{
		dest.samples.length = samples.length;
		dest.samples[] = samples[];
		dest.samplingRate = samplingRate;
	}
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
		onto.samples[i] = onto.samples[i] * sqrt(factor) +
			sqrt(1.0f - factor) * prev.samples[i];
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

IntensityLevelSpectrum whiteNoiseSpectrum(int maxFreq = 2048, int freqRes = 1)
{
	IntensityLevelSpectrum s;
	s.freqRes = freqRes;
	s.bins.length = maxFreq + 1;
	for (int i = 1; i < maxFreq; i++)
		s.bins[i] = 1.25f - 0.5f * uniform01!float();
	s.bins[0] = s.bins[$-1] = 0.0f;
	return s;
}

TimeDomainSignal whiteNoise(int sampleCount, int samplingRate, float level = 0.25f)
{
	TimeDomainSignal res;
	res.samplingRate = samplingRate;
	res.samples.length = sampleCount;
	for (size_t i = 0; i < sampleCount; i++)
		res.samples[i] = 2 * level * (uniform01!float() - 0.5f);
	return res;
}


// Shared TLS data for sound calculations
public
{
	static IntensitySpectrum s_stageIspec;
	static Spectrum s_stageSpectrum;
	static TimeDomainSignal s_stageTds;
	static TimeDomainSignal s_stageTds2;
}

private
{
	static Fft sl_fftCache;
	static Fft function() sl_fftCache_getter;
}

static this()
{
	sl_fftCache_getter = () {
		sl_fftCache = new Fft(2048);
		sl_fftCache_getter = () { return sl_fftCache; };
		return sl_fftCache;
	};
}

/// this thread's Fft cache
pragma(inline) @property Fft s_fftCache()
{
	return sl_fftCache_getter();
}


// correctness test
unittest
{
	import std.algorithm.iteration;
	import std.stdio;
	import std.range: repeat;
	import core.time;

	IntensityLevelSpectrum ss = whiteNoiseSpectrum(2048, 1);
	Spectrum s;
	Fft fftCache = new Fft(2048);
	TimeDomainSignal tds;
	assert(ss.bins.length == 2049);
	ss.genSpectrum(s);
	auto ifftStart = MonoTime.currTime;
	s.toTimeDomain(fftCache, tds);
	writeln("ifft took ", MonoTime.currTime() - ifftStart);
	assert(!isNaN(tds.samples[0].re));
	assert(!isNaN(tds.samples[0].im));
	writeln("ifft test tds sample rate: ", tds.samplingRate);
	writeWavFile("ifft_test_1bphz.wav", tds.samples.repeat(2).joiner(), 16.0f, tds.samplingRate);

	ss = whiteNoiseSpectrum(1024, 2);
	ss.genSpectrum(s);
	s.toTimeDomain(fftCache, tds);
	writeWavFile("ifft_test_2bphz.wav", tds.samples.repeat(4).joiner(), 12.0f, tds.samplingRate);

	ss = whiteNoiseSpectrum(512, 4);
	ss.genSpectrum(s);
	s.toTimeDomain(fftCache, tds);
	writeWavFile("ifft_test_4bphz.wav", tds.samples.repeat(8).joiner(), 8.0f, tds.samplingRate);
}