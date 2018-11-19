module dsubs_sound.spectrum;

import core.time;
import std.stdio: writeln;
import std.algorithm: min;
alias expi = std.complex.expi;

import dsubs_sound.common;
import dsubs_sound.wav;
import dsubs_sound.fft;
import dsubs_sound.opencl;


/// Time-domain signal
struct Tds
{
	enum int BUF_LEN = GLOBAL_SRATE;

	/// Allocate memory of the right size but do not initialize it.
	/// Value is undefined.
	this(DsubsSoundOpenclCtx ctx)
	{
		buf = Buffer(ctx, BUF_LEN * float.sizeof);
	}

	this(CommandQueue q, ref const float[BUF_LEN] samples)
	{
		buf = Buffer(q.ctx, BUF_LEN * float.sizeof);
		buf.enqueueFullWrite(q, samples[], null).release();
	}

	/// Allocate data and fill with initValue.
	this(CommandQueue q, float initValue)
	{
		buf = Buffer(q.ctx, BUF_LEN * float.sizeof);
		buf.enqueueFullFill(q, initValue, null).release();
	}

	private Buffer buf;

	pragma(inline)
	package @property auto mem() const { return buf.mem(); }

	AsyncEvent enqueueRead(CommandQueue q, float[] dest)
	{
		assert(dest.length >= BUF_LEN);
		return buf.enqueueFullRead(q, dest.ptr, null);
	}
}


enum SpectrumType
{
	INTENSITY,
	ILEVEL
}

struct EnergySpectrum(SpectrumType stype)
{
	/// Allocate memory of the right size but do not initialize it.
	/// Value is undefined.
	this(DsubsSoundOpenclCtx ctx)
	{
		buf = Buffer(ctx, BUF_LEN * float.sizeof);
	}

	/// First element of 'ilevels' is 1Hz, last is MAX_FREQ.
	this(CommandQueue q, ref const IntensityLevel[BUF_LEN] ilevels)
	{
		buf = Buffer(q.ctx, BUF_LEN * float.sizeof);
		assert(ilevels[].length == BUF_LEN);
		buf.enqueueFullWrite(q, ilevels[], null).release();
	}

	/// Allocate data and fill with initValue.
	this(CommandQueue q, float initValue)
	{
		buf = Buffer(q.ctx, BUF_LEN * float.sizeof);
		buf.enqueueFullFill(q, initValue, null).release();
	}

	enum int MAX_FREQ = GLOBAL_SRATE / 2;
	enum int BUF_LEN = MAX_FREQ;

	void patch(CommandQueue q, float value, size_t offset = 0, size_t count = BUF_LEN)
	{
		count = min(BUF_LEN - offset, count);
		buf.enqueueFill(q, value, offset, count, null).release();
	}

	private Buffer buf;

	pragma(inline)
	package @property auto mem() const { return buf.mem(); }

	/// Apply random uniform noise to frequencies in range [minFreq; maxFreq]
	void addUniformNoise(CommandQueue q, float amplitude,
		int minFreq = 1, int maxFreq = MAX_FREQ)
	{
		assert(minFreq >= 1);
		assert(maxFreq <= MAX_FREQ);
		Kernel k = q.uniformNoise;
		k.setArg(0, buf.mem);
		k.setArg(1, amplitude);
		k.setArg(2, uintSeed());
		k.enqueue(q, 1, [minFreq - 1], [maxFreq], null, null).release();
	}

	AsyncEvent enqueueRead(CommandQueue q, float[] dest)
	{
		assert(dest.length >= BUF_LEN);
		return buf.enqueueFullRead(q, dest.ptr, null);
	}

	/// Randomize phases and perform inverse discrete fourier transform.
	void toTimeDomain(CommandQueue q, ref Tds dest)
	{
		Kernel k = q.energyToPressure;
		k.setArg(0, buf.mem);
		k.setArg(1, dest.mem);
		int isILevel = stype == SpectrumType.ILEVEL ? 1 : 0;
		k.setArg(2, isILevel);
		k.setArg(3, uintSeed());
		k.enqueue(q, 1, null, [BUF_LEN], null, null).release();
		q.fft.inverse(q, dest.buf);
	}
}

alias ISpectrum = EnergySpectrum!(SpectrumType.INTENSITY);
alias ILevelSpectrum = EnergySpectrum!(SpectrumType.ILEVEL);


unittest
{
	import std.stdio;

	IntensityLevel[GLOBAL_SRATE / 2] levels;
	CommandQueue q = s_clCtx.queue(0);
	ISpectrum spec = ISpectrum(q, 0.0f);
	spec.addUniformNoise(q, 1.0f);
	spec.buf.fullRead(q, levels.ptr, null);
	writeln("OpenCL addUniformNoise test result: ", levels[0..16]);
}

unittest
{
	import std.stdio;

	Tds tds = Tds(s_clCtx);
	CommandQueue q = s_clCtx.queue(0);
	ISpectrum spec = ISpectrum(q, 0.0f);
	spec.patch(q, 20.0f, 300);
	spec.toTimeDomain(q, tds);
	float[GLOBAL_SRATE] sound;
	tds.buf.fullRead(q, sound.ptr, null);
	writeln("OpenCL toTimeDomain result: ", sound[0 .. 16]);
	writeWavFile("opencl_ifft.wav", sound[], 1.0f, GLOBAL_SRATE);
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
			Complex!float Xk1 = fromPolar((bins[k] / 2).toLinear, phases[k]);
			size_t conjk = bins.length - 1 - k;
			Complex!float Xk2 = fromPolar((bins[conjk] / 2).toLinear,
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
			Complex!float Xk1 = fromPolar(sqrt(bins[k]), phases[k]);
			size_t conjk = bins.length - 1 - k;
			Complex!float Xk2 = fromPolar(sqrt(bins[$ - 1 - k]), -phases[conjk]);
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