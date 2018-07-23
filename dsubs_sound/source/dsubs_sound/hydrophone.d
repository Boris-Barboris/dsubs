module dsubs_sound.hydrophone;

import dsubs_common.math;

import dsubs_sound.common;
import dsubs_sound.spectrum;
import dsubs_sound.water;
import dsubs_sound.soundsource;
import dsubs_sound.modulation;


struct HydrophonePrototype
{
	AntennaePrototype[] antennaes;
	int minFreq, maxFreq;
	float antennaeSpan;
	int cellCount;		// number of directional cells in each antennae
	dB directivity = 0.0f;
	dB baseNoise = 1.0f;
}

struct AntennaePrototype
{
	float rot;
}

/// Hydrophone is a collection of identical antennaes
final class Hydrophone
{
	this(Transform2D t, HydrophonePrototype p)
	{
		assert(p.minFreq >= 20 && p.maxFreq >= p.minFreq);
		m_transform = t;
		m_minFreq = p.minFreq;
		m_maxFreq = p.maxFreq;
		m_directivity = p.directivity;
		m_baseNoise = p.baseNoise;
		m_span = p.antennaeSpan;
		assert(m_span > 0.0f && m_span <= 2 * PI);
		assert(p.cellCount > 0);
		m_cellAngle = m_span / p.cellCount;
		foreach (ap; p.antennaes)
			m_ant ~= new Antennae(p.cellCount, ap.rot);
		updateSeaIntensity();
	}

	private
	{
		Transform2D m_transform;
		Antennae[] m_ant;
		int m_minFreq, m_maxFreq;
		float m_span, m_cellAngle;
		dB m_directivity;
		dB m_baseNoise;

		/// max size of sound halo
		static immutable double MAX_HALO = dgr2rad(15);
		static immutable double MAX_HALO_2 = MAX_HALO / 2;

		Intensity m_baseSeaNoise;
		Intensity m_baseFlowNoise;
	}

	/// background sea noise intensity in the hydrophone band
	void updateSeaIntensity()
	{
		float res = 0;
		for (int freq = m_minFreq; freq <= m_maxFreq; freq++)
			res += seaNoiseIL(freq).toLinear;
		res /= m_maxFreq - m_minFreq + 1;
		m_baseSeaNoise = Intensity((res.toDb + m_directivity).toLinear);
	}

	void updateFlowNoise(float kts)
	{
		float res = 0;
		for (int freq = m_minFreq; freq <= m_maxFreq; freq++)
			res += flowNoise(freq, kts).toLinear;
		res /= m_maxFreq - m_minFreq + 1;
		m_baseFlowNoise = Intensity((res.toDb + m_directivity).toLinear);
	}

	/// Continuous block of hydrophone elements
	private final class Antennae
	{
		this(int cellCount, float mainAxisRot)
		{
			assert(cellCount > 0);
			rot = mainAxisRot;
			cells.length = cellCount;
		}

		private
		{
			Intensity[] cells;
			float rot;	// rotation relative to hydrophone transform
		}

		/// reset elements array to zero energies
		void reset()
		{
			foreach (ref c; cells)
				c = Intensity(0.0f);
		}

		/// apply backround sea noise and flow noises
		void applyIsotropic()
		{
			foreach (ref c; cells)
				c += m_baseSeaNoise + m_baseFlowNoise;
		}

		/// sample cells random distribution and convert to intensity levels
		void imprint(ref IntensityLevel[] dest) const
		{
			dest.length = cells.length;
			foreach (i, ref const c; cells)
				dest[i] = IntensityLevel(c.toDb + uniform01!float * m_baseNoise);
		}

		bool sourceVisible(SoundSource s, vec2d wTargetDir)
		{
			vec2d relTargetDir = rotateVector(wTargetDir,
				-m_transform.wrotation - rot);
			double relBearing = courseAngle(relTargetDir);
			return (relBearing <= m_span / 2 + MAX_HALO_2) ||
				(relBearing >= -m_span / 2 - MAX_HALO_2);
		}
	}
}


import imageformats;

/// print passive sonar data to PNG image
private void printToPng(string filename, IntensityLevel[][] data, dB zeroLevel, dB maxLvl)
{
	import std.stdio;

	long width = data[0].length.to!long;
	long height = data.length;
	ubyte[] pixels;
	pixels.length = (width * height).to!size_t;
	size_t idx = 0;
	const float dynRange = maxLvl - zeroLevel;
	float minRaw = float.max;
	float maxRaw = -minRaw;
	for (int row = 0; row < height; row++)
		for (int col = 0; col < width; col++)
		{
			dB raw = data[row][col];
			minRaw = fmin(minRaw, raw);
			maxRaw = fmax(maxRaw, raw);
			dB transformed = (raw - zeroLevel) / dynRange;
			transformed = fmax(0.0f, fmin(1.0f, transformed));
			pixels[idx++] = (transformed * ubyte.max).to!ubyte;
		}
	write_png(filename, width, height, pixels, 1);
	writeln(filename, " written, min/max raw dB: ", minRaw, " ", maxRaw);
}


unittest
{
	HydrophonePrototype hp = HydrophonePrototype(
		[AntennaePrototype(0.0f)],
		500, 2047, dgr2rad(180.0f), 90, toDb(1.0f / 90.0f), 3.0f);
	Hydrophone h = new Hydrophone(new Transform2D(), hp);
	IntensityLevel[][] ilevels;
	ilevels.length = 90;
	float spdKts = 0.0f;
	float spdStep = 15.0f * 3.6 / 2 / ilevels.length;
	for (size_t i = 0; i < ilevels.length; i++)
	{
		h.updateFlowNoise(spdKts);
		h.m_ant[0].reset();
		h.m_ant[0].applyIsotropic();
		h.m_ant[0].imprint(ilevels[i]);
		spdKts += spdStep;
	}
	printToPng("std_hydrophone_0kts.png", ilevels, 0.0f, 120.0f);
}