module dsubs_sound.water;

import dsubs_sound.spectrum;
import dsubs_sound.common;


/// Get reference sea background noise band level
IntensityLevel seaNoiseIL(float freq)
{
	assert(freq > 0.0f);
	return IntensityLevel(70.0 - 6.0 * log2(freq / 20));
}

unittest
{
	import std.algorithm;
	import std.stdio;
	import dsubs_sound.wav;

	IntensitySpectrum ispec;
	ispec.bins.length = 2049;
	foreach (i, ref b; ispec.bins)
	{
		if (i >= 40 && i < 2048)
			b = seaNoiseIL(i) + 3.0f * uniform01!float;
		else
			b = 0.0f;
	}
	Spectrum pspec;
	ispec.genSpectrum(pspec);
	Fft fftCache = new Fft(2048);
	TimeDomainSignal tds;
	pspec.toTimeDomain(fftCache, tds);
	float maxp = tds.samples.maxElement;
	writeln("background sea noise max pressure: ", maxp);
	writeWavFile("seanoise.wav", tds.samples, 0.75f / maxp, tds.samplingRate);
}

/// Reference propagation loss coefficient
private float waterRangeDissipationK(float freq)
{
	// DMD bugs on windows produce NaNs here, that's
	// why res11-res13 are needed
	float f2 = pow(freq / 1e3, 2);
	float res11 = 0.11 * f2 / (1 + f2);
	float res12 = 44 * f2 / (4100 + f2);
	float res13 = 3e-4 * f2;
	float res = 2e-3 * (res11 + res12 + res13);
	return res;
}

private immutable float[] wrdk;

shared static this()
{
	float[] prep_wrdk;
	prep_wrdk.length = 4096;
	for (int i = 1; i <= 4096; i++)
		prep_wrdk[i - 1] = waterRangeDissipationK(i);
	wrdk = cast(immutable(float[])) prep_wrdk;
}

/// Scale intensity level of a band as if it is received underwater at range
IntensityLevel getILatRange(int freq, IntensityLevel il, float range, float dissMod = 1.0f)
{
	assert(freq > 0 && freq <= 4096);
	return IntensityLevel(il - toDb(range * range) - wrdk[freq - 1] * range * dissMod);
}

IntensityLevel getILatRange2(int freq, IntensityLevel il, float range, float rangeDb, float dissMod = 1.0f)
{
	assert(freq > 0 && freq <= 4096);
	return IntensityLevel(il - rangeDb - wrdk[freq - 1] * range * dissMod);
}

unittest
{
	IntensityLevel il = IntensityLevel(100.0f);
	auto ilDamped = getILatRange(100, il, 10000.0f);
	assert(!isNaN(ilDamped.val));
	assert(!isInfinity(ilDamped.val));
	assert(ilDamped < 100.0f);
}

/// band intensity level of flow noise
IntensityLevel flowNoise(float freq, float kts)
{
	assert(freq > 0.0f);
	assert(kts >= 0.0f, "kts is " ~ kts.to!string);
	dB res = 90.0f;
	// 18 db per knot doubling
	res += log2(kts / 10.0f) * 18.0f;
	// 9db per octave fall
	res -= 9.0f * log2(fmax(freq, 100.0f) / 1000.0f);
	return IntensityLevel(res);
}

float pointHaloAngle(float range)
{
	return dgr2rad(0.5 + uniform(-0.05f, 0.05f));
}

unittest
{
	import std.algorithm;
	import std.stdio;
	import dsubs_sound.wav;

	IntensitySpectrum ispec;
	ispec.bins.length = 2049;
	foreach (i, ref b; ispec.bins)
	{
		if (i >= 20 && i < 2048)
			b = flowNoise(i, 10.0f) + uniform(0.0f, 3.0f);
		else
			b = 0.0f;
	}
	writeln("flow noise: ", ispec.bins[19], " ", ispec.bins[$-1]);
	Spectrum pspec;
	ispec.genSpectrum(pspec);
	Fft fftCache = new Fft(2048);
	TimeDomainSignal tds;
	pspec.toTimeDomain(fftCache, tds);
	float maxp = tds.samples.maxElement;
	writeln("flow noise max pressure: ", maxp);
	writeWavFile("turbulence-flow-noise.wav", tds.samples, 0.75f / maxp, tds.samplingRate);
}