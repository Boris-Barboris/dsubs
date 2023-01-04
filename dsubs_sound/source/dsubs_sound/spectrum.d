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

	// void reduceSumSquared(CommandQueue q, ref Buffer dest, float multiplier,
	// 	uint startIndex, uint endIndex)
	// {
	// 	size_t globalSize = endIndex - startIndex;
	// 	// globalSize must be divisible by workgroup size
	// 	if (globalSize % 64)
	// 		globalSize = globalSize + 64 - (globalSize % 64);
	// 	assert(globalSize % 64 == 0);
	// 	size_t groupCount = globalSize / 64;
	// 	// Buffer globReduceBuf = Buffer(q.ctx, float.sizeof * groupCount);
	// 	Kernel k = q.mk_reduceSumSquared;
	// 	k.setArg(0, buf.mem);
	// 	k.setArg(1, q.s_reduceBuf.mem);
	// 	k.setArg(2, dest.mem);
	// 	k.setArg(3, multiplier);
	// 	k.setArg(4, endIndex);
	// 	k.enqueue(q, 1, [startIndex.to!size_t], [globalSize], [cast(size_t) 64], null);
	// }

	void reduceSumSquared(CommandQueue q, ref Buffer dest, float multiplier,
		uint startIndex, uint endIndex)
	{
		size_t globalSize = endIndex - startIndex;
		if (globalSize % 32)
			globalSize = (globalSize + 32 - globalSize % 32) / 32;
		else
			globalSize = globalSize / 32;
		// Buffer globReduceBuf = Buffer(q.ctx, float.sizeof * groupCount);
		Kernel k = q.mk_reduceSumSquared;
		k.setArg(0, buf.mem);
		k.setArg(1, q.s_reduceBuf.mem);
		k.setArg(2, dest.mem);
		k.setArg(3, multiplier);
		k.setArg(4, endIndex);
		k.enqueue(q, 1, [startIndex.to!size_t], [globalSize], [cast(size_t) 64], null);
	}

	// void reduceSumSquared(CommandQueue q, ref Buffer dest, float multiplier,
	// 	uint startIndex, uint endIndex)
	// {
	// 	Kernel k = q.mk_sumSquaredBuf;
	// 	k.setArg(0, mem);
	// 	k.setArg(1, dest.mem);
	// 	k.setArg(2, multiplier);
	// 	k.setArg(3, startIndex);
	// 	k.setArg(4, endIndex);
	// 	k.task(q, null);
	// }
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

	void copyTo(CommandQueue q, ref VarTds dest, size_t sourceOffset, size_t destOffset)
	{
		assert(sourceOffset <= length);
		buf.enqueueCopy(q, dest.buf, sourceOffset * float.sizeof, destOffset * float.sizeof,
			float.sizeof * min(dest.length - destOffset, length - sourceOffset),
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
		assert(offset < BUF_LEN);
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
	/// For the intensity spectrum with all bins fixed at 1.0 watt
	/// total (broadband) intensity (based on band summation) will be
	/// 1.0 * GLOBAL_SRATE / 2.0 watt and
	/// resulting time-domain pressure signal mean square will be 1 / GLOBAL_SRATE.
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
	/// buffer.
	// void reduceSum(CommandQueue q, ref Buffer dest,
	// 	int minFreq = 1, int endFreq = MAX_FREQ)
	// {
	// 	assert(minFreq >= 1);
	// 	assert(endFreq <= MAX_FREQ);
	// 	size_t offset = minFreq.to!uint - 1;
	// 	size_t globalSize = endFreq.to!size_t - offset;
	// 	// globalSize must be divisible by workgroup size
	// 	if (globalSize % 64)
	// 		globalSize = globalSize + 64 - (globalSize % 64);
	// 	assert(globalSize % 64 == 0);
	// 	size_t groupCount = globalSize / 64;
	// 	// Buffer globReduceBuf = Buffer(q.ctx, float.sizeof * groupCount);
	// 	Kernel k = q.mk_reduceSum;
	// 	trace(offset, " ", globalSize, " ", groupCount, " ", endFreq);
	// 	// 2133 448 7 2533
	// 	k.setArg(0, buf.mem);
	// 	k.setArg(1, q.s_reduceBuf.mem); // globReduceBuf.mem);
	// 	k.setArg(2, dest.mem);
	// 	k.setArg(3, endFreq.to!uint);
	// 	k.enqueue(q, 1, [offset], [globalSize], [cast(size_t) 64], null);
	// }

	void reduceSum(CommandQueue q, ref Buffer dest,
		int minFreq = 1, int endFreq = MAX_FREQ)
	{
		assert(minFreq >= 1);
		assert(endFreq <= MAX_FREQ);
		size_t offset = minFreq.to!uint - 1;
		size_t globalSize = endFreq.to!size_t - offset;
		if (globalSize % 32)
			globalSize = (globalSize + 32 - globalSize % 32) / 32;
		else
			globalSize = globalSize / 32;
		// Buffer globReduceBuf = Buffer(q.ctx, float.sizeof * groupCount);
		Kernel k = q.mk_reduceSum;
		k.setArg(0, buf.mem);
		k.setArg(1, q.s_reduceBuf.mem);
		k.setArg(2, dest.mem);
		k.setArg(3, endFreq.to!uint);
		k.enqueue(q, 1, [offset], [globalSize], null, null);
	}


	// void reduceSum(CommandQueue q, ref Buffer dest,
	// 	int startFreq = 1, int endFreq = MAX_FREQ)
	// {
	// 	assert(startFreq >= 1);
	// 	assert(endFreq <= MAX_FREQ);
	// 	Kernel k = q.mk_sumBuf;
	// 	k.setArg(0, buf.mem);
	// 	k.setArg(1, dest.mem);
	// 	k.setArg(2, startFreq.to!uint - 1);
	// 	k.setArg(3, endFreq.to!uint);
	// 	k.task(q, null);
	// }

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


/*

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



unittest
{
	import std.algorithm;

	CommandQueue q = s_clCtx.queue(0);
	ISpectrum source = ISpectrum(q, float.nan);
	source.buf.enqueueFill(q, 2.0f, 249, GLOBAL_SRATE / 2 - 250, null).release();
	Buffer dest = Buffer(s_clCtx, float.sizeof);
	source.reduceSum(q, dest, 250, GLOBAL_SRATE / 2 - 10);
	float res;
	dest.enqueueFullRead(q, &res, null).waitFor();
	assert(fabs(res - 2 * (GLOBAL_SRATE / 2 - 10 - 250 + 1)) < 1e-6, res.to!string);
}


unittest
{
	import std.algorithm;

	CommandQueue q = s_clCtx.queue(0);
	Tds source = Tds(q, float.nan);
	source.buf.enqueueFill(q, 1.0f, 78, 255 - 79 + 1, null).release();
	Buffer dest = Buffer(s_clCtx, float.sizeof);
	source.reduceSumSquared(q, dest, 1.0f, 79, 255);
	float res;
	dest.enqueueFullRead(q, &res, null).waitFor();
	assert(fabs(res - (255 - 79)) < 1e-6, res.to!string);
}

// __unittest_L423_C1 iter 365 1998 3666
// 2020-02-22T14:18:57.019 [trace] spectrum.d:313:reduceSum 1997 1728 27 3666

unittest
{
	import std.algorithm;

	CommandQueue q = s_clCtx.queue(0);
	ISpectrum source = ISpectrum(s_clCtx);
	float[] desiredArr;
	float[] actualArr;
	enum int ITER = 1000;
	actualArr.length = ITER;
	foreach(iter; 0..ITER)
	{
		source.patch(q, float.nan);
		float desired = uniform01!float();
		int start = uniform(1, GLOBAL_SRATE/2);
		int end = uniform(start, GLOBAL_SRATE/2);
		desiredArr ~= desired * (end - start + 1);
		source.buf.enqueueFill(q, desired, start - 1, end - start + 1, null).release();
		// trace("iter ", iter, " ", start, " ", end);
		Buffer dest = Buffer(s_clCtx, float.sizeof);
		source.reduceSum(q, dest, start, end);
		dest.enqueueFullRead(q, &actualArr[iter], null).release();
	}
	q.finish();
	foreach(iter; 0..ITER)
	{
		float res = actualArr[iter];
		float desired = desiredArr[iter];
		assert(fabs(res - desired) < 1.0f,
			res.to!string ~ " != " ~ desired.to!string ~
			" on iter " ~ iter.to!string);
	}
}

*/