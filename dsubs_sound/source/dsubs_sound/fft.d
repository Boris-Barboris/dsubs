module dsubs_sound.fft;

import std.algorithm.mutation: swap;
import std.numeric;

import dsubs_sound.common;
import dsubs_sound.opencl;


// http://www.bealto.com/gpu-fft_fft.html
// https://ocw.mit.edu/resources/res-6-008-digital-signal-processing-spring-2011/video-lectures/


/// OpenCL-backed (I)FFT kernel. N must be power of 2.
final class FFTPlan(int N = GLOBAL_SRATE)
	if (N > 1 && N <= 44000)
{
	private enum int POWER_OF_TWO = log2(N).to!int;
	static assert (pow(2, POWER_OF_TWO) == N, "N must be a power of 2");

	this(DsubsSoundOpenclCtx ctx)
	{
		m_tmpBuf = Buffer(ctx, N * 2 * float.sizeof);
	}

	private
	{
		Buffer m_tmpBuf;
	}

	/// inplace perform (i)FFT on tds buffer
	private void perform(CommandQueue q, ref Buffer tds, bool isInverse)
	{
		assert(tds.size == N * 2 * float.sizeof);
		assert(tds !is m_tmpBuf);
		Buffer* x = &tds;
		Buffer* y = &m_tmpBuf;
		Kernel k2 = isInverse ? q.iradix2 : q.radix2;
		Kernel k4 = isInverse ? q.iradix4 : q.radix4;
		int p = 1;
		// radix4
		for (; p <= N / 4; p *= 4)
		{
			k4.setArg(0, x.mem);
			k4.setArg(1, y.mem);
			k4.setArg(2, p);
			if (isInverse)
			{
				// set ifftRadix4Kernel 'last' parameter
				if (p == N / 4)
					k4.setArg(3, int(1));
				else
					k4.setArg(3, int(0));
			}
			k4.enqueue(q, 1, null, [N / 4], null, null).release();
			swap(x, y);
		}
		// radix2 for leftovers
		for (; p <= N / 2; p *= 2)
		{
			k2.setArg(0, x.mem);
			k2.setArg(1, y.mem);
			k2.setArg(2, p);
			if (isInverse)
			{
				// set ifftRadix4Kernel 'last' parameter
				if (p == N / 2)
					k2.setArg(3, int(1));
				else
					k2.setArg(3, int(0));
			}
			k2.enqueue(q, 1, null, [N / 2], null, null).release();
			swap(x, y);
		}
		// tds becomes our new staging buffer
		if (x is &m_tmpBuf)
			tds.swap(m_tmpBuf);
	}

	void forward(CommandQueue q, ref Buffer tds) { perform(q, tds, false); }
	void inverse(CommandQueue q, ref Buffer tds) { perform(q, tds, true); }
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
	enum int fftSize = GLOBAL_SRATE / 2;

	float2[] noise = new float2[fftSize];
	float2[] spectrum = new float2[fftSize];
	for (int i = 0; i < noise.length; i++)
	{
		noise[i].re = uniform(-1.0f, 1.0f);
		noise[i].im = uniform(-1.0f, 1.0f);
	}

	Fft checker = new Fft(fftSize);
	float2[] reference = checker.fft!(float)(noise);

	DsubsSoundOpenclCtx ctx = s_clCtx;
	CommandQueue mainQueue = ctx.queue(0);
	auto plan = new FFTPlan!(fftSize)(ctx);
	Buffer sbuf = Buffer(mainQueue, noise);
	Buffer sourceCopy = Buffer(ctx, sbuf.size);
	sbuf.enqueueCopy(mainQueue, sourceCopy, null).release();
	mainQueue.finish();

	int fftCount = 256;
	auto startAt = MonoTime.currTime();
	for (int i = 0; i < fftCount; i++)
	{
		sourceCopy.enqueueCopy(mainQueue, sbuf, null).release();
		plan.forward(mainQueue, sbuf);
	}
	mainQueue.finish();
	writeln(fftCount, " ffts took ", MonoTime.currTime - startAt, " on OpenCL");
	sbuf.fullRead(mainQueue, spectrum.ptr, null);

	for (int i = 0; i < spectrum.length; i++)
	{
		scope (failure)	writeln("fft mismatch ", reference[i], " with ", spectrum[i]);
		assert(fabs(reference[i].re - spectrum[i].re) < 1e-4);
		assert(fabs(reference[i].im - spectrum[i].im) < 1e-4);
	}

	// test ifft
	plan.inverse(mainQueue, sbuf);
	float2[] generatedNoise = new float2[noise.length];
	sbuf.fullRead(mainQueue, generatedNoise.ptr, null);

	for (int i = 0; i < generatedNoise.length; i++)
	{
		scope (failure)	writeln("ifft mismatch ", noise[i], " with ", generatedNoise[i]);
		assert(fabs(noise[i].re - generatedNoise[i].re) < 1e-4);
		assert(fabs(noise[i].im - generatedNoise[i].im) < 1e-4);
	}
}