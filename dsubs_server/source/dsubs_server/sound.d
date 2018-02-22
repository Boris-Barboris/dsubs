module dsubs_server.sound;

import std.algorithm;
import std.math;

import dsubs_common.api.constants;
import dsubs_common.math;

import dsubs_server.rng;


alias watt = float;	/// 1.0 'watt' is equal to intensity of 6.67e-19 W/m^2
alias dB = float;	/// re 1uPa, intensity of 6.67e-19 W/m^2
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
		// scale from 1Hz band to actual band size
		g_baseSeaNoiseDb[i] += freqBinWidth(i).toDb;
		float seaNoiseWatt = toIntensity(g_baseSeaNoiseDb[i]);
		g_baseSeaNoise[i] = RolledWatt(seaNoiseWatt, 0.05f * seaNoiseWatt);
	}
}

dB toIntensityLevel(watt intensity)
{
	assert(intensity > 0.0, "non-positive intensity");
	return 10.0f * log10(intensity);
}

alias toDb = toIntensityLevel;

watt toIntensity(dB ilevel)
{
	return pow(10.0f, ilevel * 0.1f);
}

alias fromDb = toIntensity;

/// universal sound intensity level reduction, caused by range and propagation losses.
dB getIntensityLevelAtRange(int freqBin, dB ilevel, double range)
{
	return ilevel - toDb(range * range) - g_freqDissipation[freqBin] * range;
}

private float freqBinWidth(int bin)
{
	return FREQ_BIN_BORDERS[bin + 1] - FREQ_BIN_BORDERS[bin];
}

//dB totalBandLevel(ref const watt[FREQ_BIN_COUNT] )

/// Entity wich can generate noise
class NoiseGenerator
{
	/// Watt per unit body angle, not omnidirectional watt
	RolledWatt[FREQ_BIN_COUNT] baseProfile;
	protected watt[FREQ_BIN_COUNT] m_curNoise;

	/// global emission gain
	float generationK = 1.0f;

	invariant
	{
		assert(generationK >= 0.0f, "negative noise generationK gain");
	}

	/// Roll randoms and generate intensities from the baseProfle
	void instantiate()
	{
		foreach (i, level; baseProfile)
			m_curNoise[i] = generationK * level.roll();
	}

	/// Calculate sound intensity towards the course 'dir' and
	/// add it to output.
	abstract void addNoisePowerTo(double dir, ref watt[FREQ_BIN_COUNT] output);
}

/// Noise is omnidirectional
class OmniNoise: NoiseGenerator
{
	override void addNoisePowerTo(double dir, ref watt[FREQ_BIN_COUNT] output)
	{
		for (int i = 0; i < FREQ_BIN_COUNT; i++)
			output[i] += m_curNoise[i];
	}
}

/// Cosine direction law for noise generation, usefull for propulsors.
class CosineDirectedNoise: NoiseGenerator
{
	private float m_backNoiseK = 0.0f;
	Transform2D transform;

	/// positive for backwards noise emission
	@property float backNoiseK(float rhs)
	{
		assert(fabs(rhs) <= 0.5f);
		return m_backNoiseK = rhs;
	}

	this(Transform2D t)
	{
		transform = t;
	}

	override void addNoisePowerTo(double dir, ref watt[FREQ_BIN_COUNT] output)
	{
		float k = 1.0f - fabs(m_backNoiseK) - m_backNoiseK * cos(dir - transform.wrotation);
		assert(k >= 0.0, "negative back-directed noise");
		for (int i = 0; i < FREQ_BIN_COUNT; i++)
			output[i] += m_curNoise[i] * k;
	}
}