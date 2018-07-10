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
	ispec.bins.length = 2047;
	foreach (i, ref b; ispec.bins)
	{
		if (i > 39)
			b = seaNoiseIL(i + 1) + 3.0f * uniform01!float;
		else
			b = 0.0f;
	}
	Spectrum pspec;
	ispec.genSpectrum(pspec);
	Fft fftCache = new Fft(4096);
	TimeDomainSignal tds;
	pspec.toTimeDomain(fftCache, tds);
	float maxp = tds.samples.map!(a => a.re).maxElement;
	writeln("background sea noise max pressure: ", maxp);
	writeWavFile("seanoise.wav", tds.samples, 0.75f / maxp, tds.samplingRate);
}

/// Reference propagation loss coefficient
private float waterRangeDissipationK(float freq)
{
	float f2 = pow(freq / 1e3, 2);
	return 2e-3 * (0.11 * f2 / (1 + f2) +
		44 * f2 / (4100 + f2) + 3e-4 * f2);
}

/// Scale intensity level of a band as if it is received underwater at range
IntensityLevel getILatRange(float freq, IntensityLevel il, float range, float dissMod = 1.0f)
{
	return IntensityLevel(il - toDb(range * range) - waterRangeDissipationK(freq) * range * dissMod);
}

unittest
{
	IntensityLevel il = IntensityLevel(100.0f);
	auto ilDamped = getILatRange(100.0f, il, 10000);
	assert(!isNaN(ilDamped.val));
	assert(!isInfinity(ilDamped.val));
	assert(ilDamped < 100.0f);
}

/// band intensity level of flow noise
IntensityLevel flowNoise(float freq, float speed, float spdMod = 1.0f)
{
	float kts = speed * 3.6 / 2;
	float res = 90.0f;
	// 1.8 db per knot
	res += (kts - 10.0f) * 1.8f * spdMod;
	// 9db per ofcave fall
	res -= 9.0f * log2(freq / 1000.0f);
	return IntensityLevel(res);
}