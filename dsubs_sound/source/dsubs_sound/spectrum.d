module dsubs_sound.spectrum;

import core.time;
import std.stdio: writeln;
import std.algorithm: min;
alias expi = std.complex.expi;

import dsubs_sound.common;
import dsubs_sound.wav;
import dsubs_sound.fft;
import dsubs_sound.opencl;


/// Time-domain signal of 1 second length
struct Tds
{
	enum size_t BUF_LEN = GLOBAL_SRATE;

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

	@disable this(this);

	private Buffer buf;

	void release() @nogc nothrow { buf.release(); }

	pragma(inline)
	package @property auto mem() const { return buf.mem(); }

	AsyncEvent enqueueRead(CommandQueue q, float[] dest)
	{
		assert(dest.length >= BUF_LEN);
		return buf.enqueueFullRead(q, dest.ptr, null);
	}

	/// blocking read
	void read(CommandQueue q, float[] dest)
	{
		assert(dest.length >= BUF_LEN);
		buf.fullRead(q, dest.ptr, null);
	}

	void addTo(CommandQueue q, ref Tds dest)
	{
		Kernel k = q.mk_addTo;
		k.setArg(0, mem);
		k.setArg(1, dest.mem);
		k.setArg(2, 0);
		k.enqueue(q, 1, null, [BUF_LEN], null, null);
	}

	void swapWith(ref Tds rhs)
	{
		buf.swapWith(rhs.buf);
	}

	void fill(CommandQueue q, float val)
	{
		buf.enqueueFullFill(q, val, null).release();
	}

	void interpolateIntensity(CommandQueue q, float start, float end)
	{
		Kernel k = q.mk_interpolateIntensity;
		k.setArg(0, mem);
		k.setArg(1, start);
		k.setArg(2, end);
		k.enqueue(q, 1, null, [GLOBAL_SRATE], null, null);
	}
}


/// Time-domain signal of variable length
struct VarTds
{
	/// Allocate memory of the right size but do not initialize it.
	this(DsubsSoundOpenclCtx ctx, size_t lgth)
	{
		buf = Buffer(ctx, lgth * float.sizeof);
	}

	this(CommandQueue q, const float[] samples)
	{
		buf = Buffer(q.ctx, samples.length * float.sizeof);
		buf.enqueueFullWrite(q, samples, null).release();
	}

	/// Allocate data and fill with initValue.
	this(CommandQueue q, size_t lgth, float initValue)
	{
		buf = Buffer(q.ctx, lgth * float.sizeof);
		buf.enqueueFullFill(q, initValue, null).release();
	}

	@disable this(this);

	private Buffer buf;

	void release() @nogc nothrow { buf.release(); }

	@property size_t length() const { return buf.size / float.sizeof; }

	pragma(inline)
	package @property auto mem() const { return buf.mem(); }

	AsyncEvent enqueueRead(CommandQueue q, float[] dest)
	{
		assert(dest.length >= length);
		return buf.enqueueFullRead(q, dest.ptr, null);
	}

	/// blocking read
	void read(CommandQueue q, float[] dest)
	{
		assert(dest.length >= length);
		buf.fullRead(q, dest.ptr, null);
	}

	void addTo(CommandQueue q, ref Tds dest, size_t startIdx)
	{
		assert(startIdx <= length);
		Kernel k = q.mk_addTo;
		k.setArg(0, mem);
		k.setArg(1, dest.mem);
		k.setArg(2, startIdx.to!int);
		k.enqueue(q, 1, null, [min(dest.BUF_LEN, length - startIdx)], null, null);
	}

	void copyTo(CommandQueue q, ref Tds dest, size_t sourceOffset, size_t destOffset)
	{
		assert(sourceOffset <= length);
		buf.enqueueCopy(q, dest.buf, sourceOffset * float.sizeof, destOffset * float.sizeof,
			float.sizeof * min(dest.BUF_LEN - destOffset, length - sourceOffset),
			null).release();
	}

	void swapWith(ref VarTds rhs)
	{
		// length check inside buffer swap
		buf.swapWith(rhs.buf);
	}

	void fill(CommandQueue q, float val)
	{
		buf.enqueueFullFill(q, val, null).release();
	}

	void interpolateIntensity(CommandQueue q, float start, float end)
	{
		Kernel k = q.mk_interpolateIntensity;
		k.setArg(0, mem);
		k.setArg(1, start);
		k.setArg(2, end);
		k.enqueue(q, 1, null, [length], null, null);
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

	static if (stype == SpectrumType.INTENSITY)
		private alias ElT = Intensity;
	else
		private alias ElT = IntensityLevel;

	/// First element of 'ilevels' is 1Hz, last is MAX_FREQ.
	this(CommandQueue q, ref const ElT[BUF_LEN] ilevels)
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

	@disable this(this);

	enum int MAX_FREQ = GLOBAL_SRATE / 2;
	enum int BUF_LEN = MAX_FREQ;

	void patch(CommandQueue q, float value, size_t offset = 0, size_t count = BUF_LEN)
	{
		count = min(BUF_LEN - offset, count);
		buf.enqueueFill(q, value, offset, count, null).release();
	}

	private Buffer buf;

	void release() @nogc nothrow { buf.release(); }

	pragma(inline)
	package @property auto mem() const { return buf.mem(); }

	/// Apply random uniform noise to frequencies in range [minFreq; maxFreq]
	void addUniformNoise(CommandQueue q, float amplitude,
		int minFreq = 1, int maxFreq = MAX_FREQ)
	{
		assert(minFreq >= 1);
		assert(maxFreq <= MAX_FREQ);
		Kernel k = q.mk_uniformNoise;
		k.setArg(0, buf.mem);
		k.setArg(1, amplitude);
		k.setArg(2, uintSeed());
		k.enqueue(q, 1, [minFreq - 1], [maxFreq - minFreq + 1], null, null);
	}

	AsyncEvent enqueueRead(CommandQueue q, float[] dest)
	{
		assert(dest.length >= BUF_LEN);
		return buf.enqueueFullRead(q, dest.ptr, null);
	}

	/// Randomize phases and perform inverse discrete fourier transform.
	void toTimeDomain(CommandQueue q, ref Tds dest)
	{
		Kernel k = q.mk_energyToPressure;
		k.setArg(0, buf.mem);
		k.setArg(1, dest.mem);
		int isILevel = stype == SpectrumType.ILEVEL ? 1 : 0;
		k.setArg(2, isILevel);
		k.setArg(3, uintSeed());
		k.enqueue(q, 1, null, [BUF_LEN], null, null);
		q.fft.inverse(q, dest.buf);
	}

	/// Sum bins of frequencies from startFreq to endFreq and write result to dest
	/// buffer
	void reduceSum(CommandQueue q, ref Buffer dest,
		int startFreq = 1, int endFreq = MAX_FREQ)
	{
		assert(startFreq >= 1);
		assert(endFreq <= MAX_FREQ);
		Kernel k = q.mk_sumBuf;
		k.setArg(0, buf.mem);
		k.setArg(1, dest.mem);
		k.setArg(2, startFreq.to!uint - 1);
		k.setArg(3, endFreq.to!uint);
		k.task(q, null);
	}

	void addTo(CommandQueue q, ref EnergySpectrum!(stype) dest,
		int minFreq = 1, int maxFreq = MAX_FREQ)
	{
		Kernel k = q.mk_addTo;
		k.setArg(0, mem);
		k.setArg(1, dest.mem);
		k.setArg(2, 0);
		k.enqueue(q, 1, [minFreq - 1], [maxFreq - minFreq + 1], null, null);
	}
}

alias ISpectrum = EnergySpectrum!(SpectrumType.INTENSITY);
alias ILevelSpectrum = EnergySpectrum!(SpectrumType.ILEVEL);


unittest
{
	IntensityLevel[GLOBAL_SRATE / 2] levels;
	CommandQueue q = s_clCtx.queue(0);
	ISpectrum spec = ISpectrum(q, 0.0f);
	spec.addUniformNoise(q, 1.0f);
	spec.buf.fullRead(q, levels.ptr, null);
	trace("OpenCL addUniformNoise test result: ", levels[0..16]);
}

unittest
{
	Tds tds = Tds(s_clCtx);
	CommandQueue q = s_clCtx.queue(0);
	ISpectrum spec = ISpectrum(q, 0.0f);
	spec.patch(q, 20.0f, 300);
	spec.toTimeDomain(q, tds);
	float[GLOBAL_SRATE] sound;
	tds.buf.fullRead(q, sound.ptr, null);
	trace("OpenCL toTimeDomain result: ", sound[0 .. 16]);
	writeWavFile("opencl_ifft.wav", sound[], 1.0f, GLOBAL_SRATE);
}


// energy conservation tests
unittest
{
	import std.algorithm;

	Tds tds = Tds(s_clCtx);
	CommandQueue q = s_clCtx.queue(0);
	ISpectrum spec = ISpectrum(q, GLOBAL_SRATE);
	spec.toTimeDomain(q, tds);
	float[GLOBAL_SRATE] sound;
	tds.buf.fullRead(q, sound.ptr, null);
	trace("4096 spectrum max pressure: ", sound[].map!(s => s.abs).maxElement);
	trace("4096 spectrum mean square pressure: ", sound[].map!(s => s * s).sum / GLOBAL_SRATE);
}