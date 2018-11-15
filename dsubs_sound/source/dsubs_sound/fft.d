module dsubs_sound.fft;

import std.numeric;

import dsubs_sound.common;
import dsubs_sound.opencl;
import dsubs_sound.tds;


// http://www.bealto.com/gpu-fft_fft.html


/// OpenCL-backed FFT optimization cache. N must be power of 2.
final class FFTPlan(int N = GLOBAL_SRATE)
{
	this(DsubsSoundOpenclCtx ctx)
	{
		m_tmpBuf = new Buffer(ctx, N * 2 * float.sizeof);
	}

	private
	{
		Buffer m_tmpBuf;
	}

	Buffer forward(CommandQueue q, Buffer tds)
	{
		assert(tds.size == N * 2 * float.sizeof);
		assert(tds !is m_tmpBuf);
		Buffer x = tds;
		Buffer y = m_tmpBuf;
		Buffer tmp = null;
		Kernel k = q.radix2;
		for (int p = 1; p <= N / 2; p *= 2)
		{
			k.setArg(0, x.mem);
			k.setArg(1, y.mem);
			k.setArg(2, p);
			k.enqueue(q, 1, null, [N / 2], null, null).release();
			tmp = x;
			x = y;
			y = tmp;
		}
		// tds becomes our new staging buffer
		if (x is m_tmpBuf)
			m_tmpBuf = tds;
		return x;
	}
}

unittest
{
	import std.stdio;
	import std.algorithm: map;
	import std.range: chain;
	import core.time: MonoTime;
	import dsubs_sound.filter;
	import dsubs_sound.wav;

	alias float2 = Complex!float;

	float2[] noise = new float2[GLOBAL_SRATE];
	for (int i = 0; i < noise.length; i++)
	{
		noise[i].re = uniform(-1.0f, 1.0f);
		noise[i].im = 0.0f;
	}

	Fft checker = new Fft(GLOBAL_SRATE);
	float2[] reference = checker.fft!(float)(noise);

	DsubsSoundOpenclCtx ctx = s_clCtx;
	CommandQueue mainQueue = ctx.queue(0);
	FFTPlan!GLOBAL_SRATE plan = new FFTPlan!GLOBAL_SRATE(ctx);
	Buffer sbuf = new Buffer(mainQueue, noise);
	Buffer sourceCopy = new Buffer(ctx, sbuf.size);
	sbuf.enqueueCopy(mainQueue, sourceCopy, null).release();
	mainQueue.finish();

	int fftCount = 256;
	auto startAt = MonoTime.currTime();
	Buffer res;
	for (int i = 0; i < fftCount; i++)
	{
		sourceCopy.enqueueCopy(mainQueue, sbuf, null).release();
		res = plan.forward(mainQueue, sbuf);
	}
	mainQueue.finish();
	writeln(fftCount, " ffts took ", MonoTime.currTime - startAt, " on OpenCL");
	res.fullRead(mainQueue, noise.ptr, null);

	for (int i = 0; i < noise.length; i++)
	{
		scope (failure)	writeln("fft mismatch ", reference[i], " with ", noise[i]);
		assert(fabs(reference[i].re - noise[i].re) < 1e-2);
		assert(fabs(reference[i].im - noise[i].im) < 1e-2);
	}
}