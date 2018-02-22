module dsubs_server.sound;

import std.algorithm;
import std.math;

import dsubs_common.api.constants;
import dsubs_common.math;

import dsubs_server.rng;


alias watt = float;
alias dB = float;
alias RolledWatt = RolledF;

private __gshared
{
	/// signal of frequency in the bin is decreased on that many decibels for each
	/// meter of travel.
	float[FREQ_BIN_COUNT] g_freqDissipation;

	/// Omnidirectional power of background sea noise
	dB[FREQ_BIN_COUNT] g_baseSeaNoiseDb;
	RolledWatt[FREQ_BIN_COUNT] g_baseSeaNoise;
}

shared static this()
{
	for (int i = 0; i < FREQ_BIN_COUNT; i++)
	{
		g_freqDissipation[i] = 1e-5 + FREQ_BINS[i] * FREQ_BINS[i] * 1e-8;
		g_baseSeaNoiseDb[i] = 75.0f - 7.0f * log2(FREQ_BINS[i] / float(FREQ_BINS[0]));
		float seaNoiseWatt = toWatt(g_baseSeaNoiseDb[i]);
		g_baseSeaNoise[i] = RolledWatt(seaNoiseWatt, 0.1f * seaNoiseWatt);
	}
}

dB toIntensity(watt power)
{
	assert(power > 0.0, "non-positive power");
	return 10.0f * log10(power);
}

watt toWatt(dB intensity)
{
	return pow(10.0f, intensity * 0.1f);
}

/// universal sound intensity reduction, caused by range between source and sensor
dB getIntensityAtRange(int freqBin, dB intensity, double range)
{
	return intensity - toIntensity(range * range) - g_freqDissipation[freqBin] * range;
}


/// Entity wich can generate noise
class NoiseGenerator
{
	/// Watt per unit body angle, not omnidirectional watt
	RolledWatt[FREQ_BIN_COUNT] baseProfile;

	/// global emission gain
	float generationK = 1.0f;

	invariant
	{
		assert(generationK >= 0.0f, "negative noise generationK gain");
	}

	/// Calculate absolute noise emission intensity towards the course 'dir' and
	/// add it to output.
	abstract void addNoisePowerTo(double dir, ref watt[FREQ_BIN_COUNT] output);
}

/// Noise is omnidirectional
class OmniNoise: NoiseGenerator
{
	override void addNoisePowerTo(double dir, ref watt[FREQ_BIN_COUNT] output)
	{
		foreach (i, level; baseProfile)
			output[i] = generationK * level;
	}
}

/// Cosine direction law for noise generation, usefull for propulsors
class CosinDirectedNoise: NoiseGenerator
{
	float backNoiseK = 0.0f;
	Transform2D transform;

	this(Transform2D t)
	{
		transform = t;
	}

	override void addNoisePowerTo(double dir, ref watt[FREQ_BIN_COUNT] output)
	{
		float k = 1.0f + backNoiseK * cos(dir - transform.rotation);
		assert(k >= 0.0, "negative back-directed noise");
		foreach (i, level; baseProfile)
			output[i] = generationK * k * level;
	}
}