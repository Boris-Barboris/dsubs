module dsubs_sound.hydrophone;

import std.algorithm.comparison: min, max;
import std.algorithm.iteration: sum;

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
	float directivity = 0.0f;
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
		float m_directivity;
		dB m_baseNoise;

		/// max size of sound halo
		static immutable double MAX_HALO = dgr2rad(20);
		static immutable double MAX_HALO_2 = MAX_HALO / 2;

		Intensity m_baseSeaNoise;
		Intensity m_baseFlowNoise;
		// spectrum cache for precalculations
		IntensitySpectrum m_ispecCache;
	}

	/// background sea noise intensity in the hydrophone band
	void updateSeaIntensity()
	{
		float res = 0;
		for (int freq = m_minFreq; freq <= m_maxFreq; freq++)
			res += seaNoiseIL(freq).toLinear;
		res /= m_maxFreq - m_minFreq + 1;
		m_baseSeaNoise = Intensity(res * m_directivity);
	}

	void updateFlowNoise(float kts)
	{
		float res = 0;
		for (int freq = m_minFreq; freq <= m_maxFreq; freq++)
			res += 0.01 * flowNoise(freq, kts).toLinear;
		res /= m_maxFreq - m_minFreq + 1;
		m_baseFlowNoise = Intensity(res * m_directivity);
	}

	/// reset antennaes and apply isotropic noises
	void resetAndIsotropic()
	{
		foreach (a; m_ant)
		{
			a.reset();
			a.applyIsotropic();
		}
	}

	void applySoundSource(SoundSource s)
	{
		vec2d dir = s.transform.wposition - m_transform.wposition;
		double range = dir.length;
		foreach (a; m_ant)
		{
			double relBearing;
			if (a.sourceVisible(dir, relBearing))
				a.applySoundSource(s, range, relBearing);
		}
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
			{
				dest[i] = IntensityLevel(c.toDb + uniform(0.0f, m_baseNoise));
				assert(!isNaN(dest[i].val));
			}
		}

		bool sourceVisible(vec2d wTargetDir, out double relBearing)
		{
			vec2d relTargetDir = rotateVector(wTargetDir,
				-m_transform.wrotation - rot);
			relBearing = courseAngle(relTargetDir);
			return (relBearing <= m_span / 2 + MAX_HALO_2) ||
				(relBearing >= -m_span / 2 - MAX_HALO_2);
		}

		void applySoundSource(SoundSource s, double range, double relBearing)
		{
			relBearing = -relBearing;	// let's assume that left cell starts at negative
			s.getIntensitySpectrum(m_transform.wposition, m_ispecCache, m_minFreq, m_maxFreq, 4.0f);
			float bandSum = m_ispecCache.bins.sum() / (m_maxFreq - m_minFreq + 1);
			// half of halo size
			float haloBase = s.radius / range;
			float haloBound = fmin(3.0 * haloBase, MAX_HALO);
			// relative bearing of left edge of first cell from the left
			float arrayA0 = -m_span / 2;
			// first cell we'll add energy to
			int cellStart = max(0, floor((relBearing - haloBound - arrayA0) / m_cellAngle).to!int);
			// last cell we'll add energy to
			int cellEnd = min(cells.length - 1, floor((relBearing + haloBound - arrayA0) / m_cellAngle).to!int);
			for (int ci = cellStart; ci <= cellEnd; ci++)
			{
				float cellLeft = arrayA0 + ci * m_cellAngle;
				float cellRight = cellLeft + m_cellAngle;
				float relLeft = (cellLeft - relBearing) / haloBase;
				float relRight = (cellRight - relBearing) / haloBase;
				assert(relRight >= relLeft);
				cells[ci] += bandSum * 0.5 * (erf(relRight) - erf(relLeft));
			}
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
		500, 2047, dgr2rad(180.0f), 90, 1.0f / 90.0f, 3.0f);
	Hydrophone h = new Hydrophone(new Transform2D(), hp);
	IntensityLevel[][] ilevels;
	ilevels.length = 90;
	float spdKts = 0.0f;
	float spdStep = 15.0f * 3.6 / 2 / ilevels.length;
	for (size_t i = 0; i < ilevels.length; i++)
	{
		h.updateFlowNoise(spdKts);
		h.resetAndIsotropic();
		h.m_ant[0].imprint(ilevels[i]);
		spdKts += spdStep;
	}
	printToPng("std_hydrophone_0-15ms.png", ilevels, 0.0f, 90.0f);
}

unittest
{
	import std.array;
	import std.algorithm: map, maxElement;
	import std.range;
	import std.stdio;
	import dsubs_sound.image;
	import dsubs_sound.wav;

	Transform2D propTrans = new Transform2D();
	PropellerSound prop = new PropellerSound(propTrans, stdPropellerProto());
	float freqPerMs = 2.0f / 17.0f;
	float[] speeds = [1.0f, 3.0f, 5.0f, 7.5f, 10.0f, 12.5f, 15.0f, 17.0f];
	float[] relBearings = iota(0, speeds.length).map!(
		i => (dgr2rad(75) - i * dgr2rad(150) / (speeds.length - 1)).to!float).array;
	writeln("relative bearings: ", relBearings);

	HydrophonePrototype hp = HydrophonePrototype(
		[AntennaePrototype(0.0f)],
		500, 2047, dgr2rad(180.0f), 181, 4 / 181.0f, 3.0f);
	Hydrophone h = new Hydrophone(new Transform2D(), hp);
	IntensityLevel[][] ilevels;
	ilevels.length = 500;
	float spdKts = 5.0f;
	for (size_t i = 0; i < ilevels.length; i++)
	{
		h.updateFlowNoise(spdKts);
		h.resetAndIsotropic();
		if (i == 0)
			writeln("std_propeller speed/freq/normalVel:");
		foreach (j, float spd; speeds)
		{
			float freq = spd * freqPerMs;
			prop.preUpdate(freq, spd);
			if (i == 0)
				writeln(spd, "\t", freq, "\t", prop.normalVel);
			prop.postUpdate(freq);
			propTrans.position = rotateVector(vec2d(0.0, (i + 1) * 200.0), relBearings[j]);
			h.applySoundSource(prop);
		}
		h.m_ant[0].imprint(ilevels[i]);
	}
	printToPng("std_hydrophone_vs_std_propeller_50km.png", ilevels, 0.0f, 90.0f);

	// generate sound sample of std_propeller on 1km range
	propTrans.position = vec2d(0.0, 1000.0);
	IntensitySpectrum ispec;
	prop.getIntensitySpectrum(vec2d(0, 0), ispec, 500, 2047, 4.0f);
	Fft fftCache = new Fft(4096);
	Spectrum pspec;
	ispec.genSpectrum(pspec);
	TimeDomainSignal tds;
	pspec.toTimeDomain(fftCache, tds);
	tds.samples = tds.samples.cycle.takeExactly(4096 * 5).array;
	prop.modulator.modulate(tds);
	float maxp = tds.samples.map!(a => a.re).maxElement;
	writeln("std_hydrophone_vs_std_propeller_1km maxp: ", maxp);
	writeWavFile("std_hydrophone_vs_std_propeller_1km.wav", tds.samples, 0.9f / maxp, tds.samplingRate);
}