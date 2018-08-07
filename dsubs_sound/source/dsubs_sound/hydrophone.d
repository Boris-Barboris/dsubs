module dsubs_sound.hydrophone;

import std.algorithm.comparison: min, max;
import std.algorithm.iteration: sum;

import dsubs_common.math;
import dsubs_common.event;
import dsubs_common.api.entities;

import dsubs_sound.common;
import dsubs_sound.spectrum;
import dsubs_sound.water;
import dsubs_sound.soundsource;
import dsubs_sound.modulation;


struct HydrophonePrototype
{
	float[] antennaeRots;
	int minFreq, maxFreq;
	float antennaeSpan;
	int cellCount;
	float directivity;
	dB baseNoise = 3.0f;
	float bearingErrNoise = 0.001f;
	float flowNoiseMult = 0.001f;
}


/// Hydrophone is a collection of identical antennaes
final class Hydrophone
{
	this(Transform2D t, ref const HydrophonePrototype p)
	{
		assert(p.minFreq >= 20 && p.maxFreq >= p.minFreq);
		m_transform = t;
		m_minFreq = p.minFreq;
		m_maxFreq = p.maxFreq;
		m_srate = (m_maxFreq + 1) * 2;
		m_directivity = p.directivity;
		m_baseNoise = p.baseNoise;
		m_span = p.antennaeSpan;
		m_bearingErrNoise = p.bearingErrNoise;
		m_flowNoiseMult = p.flowNoiseMult;
		assert(m_span > 0.0f && m_span < 2 * PI - MAX_HALO);
		assert(p.cellCount > 0);
		m_cellAngle = m_span / p.cellCount;
		foreach (rot; p.antennaeRots)
			m_ant ~= new Antennae(p.cellCount, rot);
	}

	private
	{
		Transform2D m_transform;
		Antennae[] m_ant;
		int m_minFreq, m_maxFreq, m_srate;
		float m_span, m_cellAngle;
		float m_directivity;
		float m_bearingErrNoise;
		float m_flowNoiseMult;
		dB m_baseNoise;

		/// max size of sound halo
		enum float MAX_HALO = dgr2rad(20);
		enum float MAX_HALO_2 = MAX_HALO / 2;
		enum float ISOTROPIC_VAR = 2.0;

		// broadband sea background noise intensity
		Intensity m_baseSeaNoise;
		// broadband flow noise intensity
		Intensity m_baseFlowNoise;

		// true when the player is listening signals from this hydrophone
		bool m_hasListener;
		// world-space direction the player is listening to
		float m_listenDir = 0.0f;
		// false when no active antenna has a cell for chosen listen Dir
		bool m_listenDirValid;

		// time domain signals that are generated for listening player
		TimeDomainSignal m_prevTds;
		TimeDomainSignal m_curTds;
		static IntensitySpectrum s_stageIspec;
		static Spectrum s_stageSpectrum;
		static TimeDomainSignal s_stageTds;
		static Fft s_fftCache;
	}

	Event!(void delegate()) onPreApply;

	// makes sure TLS fft cache is constructed
	private void ensureTlsCache()
	{
		if (s_fftCache is null)
			s_fftCache = new Fft(4096);
	}

	@property Transform2D transform() { return m_transform; }

	@property bool hasListener() const { return m_hasListener; }

	@property bool listenDirValid() const { return m_listenDirValid; }

	@property size_t antennaCount() const { return m_ant.length; }

	@property void hasListener(bool rhs)
	{
		m_hasListener = rhs;
		if (!rhs)
			m_listenDirValid = false;
	}

	/// set world-space direction the user wants to listen to
	@property void listenDir(float rhs)
	{
		enforce(!isNaN(rhs), "Nan direction");
		enforce(!isInfinity(rhs), "Infinity direction");
		m_listenDir = clampAnglePi(rhs);
	}

	@property float listenDir() const { return m_listenDir; }

	/// finalize m_curTds by overlapping it with m_prevTds and applying noise
	const(TimeDomainSignal) finalizeListenTds()
	{
		assert(m_listenDirValid);
		float linNoise = m_baseNoise.toLinear;
		foreach (ref s; m_curTds.samples)
			s.re += uniform(-linNoise, linNoise);
		if (m_prevTds.samples.length)
			overlapTDS(m_prevTds, m_curTds, m_srate / 4);
		return m_curTds;
	}

	immutable(short)[] finalizePcbData(out int srate, float maxp = 1e5)
	{
		const(TimeDomainSignal) tds = finalizeListenTds();
		srate = tds.samplingRate;
		short[] res = new short[tds.samples.length];
		for (size_t i = 0; i < res.length; i++)
		{
			res[i] = max(short.min, min(short.max,
				lrint(tds.samples[i].re / maxp * short.max))).to!short;
		}
		return cast(immutable(short)[]) res;
	}

	// recalculate listening cell according to current transform rotation
	private void updateListenCell()
	{
		m_listenDirValid = false;
		foreach (ant; m_ant)
		{
			if (m_listenDirValid)
			{
				ant.listenCell = -1;
				continue;
			}
			double relBearing = clampAnglePi(
				m_listenDir - m_transform.wrotation - ant.rot);
			bool belongs = (relBearing <= m_span / 2) && (relBearing >= -m_span / 2);
			if (belongs)
			{
				m_listenDirValid = true;
				ant.listenCell = ant.relBearingToCell(relBearing);
			}
			else
				ant.listenCell = -1;
		}
	}

	private void updateSeaIntensity()
	{
		float res = 0;
		for (int freq = m_minFreq; freq <= m_maxFreq; freq++)
		{
			float rngm = uniform(-ISOTROPIC_VAR, ISOTROPIC_VAR);
			float intensity = (seaNoiseIL(freq) + rngm).toLinear;
			res += intensity;
			if (m_listenDirValid)
				s_stageIspec.bins[freq - 1] += intensity;
		}
		res /= m_maxFreq + 1;
		m_baseSeaNoise = Intensity(res * m_directivity);
	}

	private void updateFlowNoise(float kts)
	{
		float res = 0;
		for (int freq = m_minFreq; freq <= m_maxFreq; freq++)
		{
			float rngm = uniform(-ISOTROPIC_VAR, ISOTROPIC_VAR);
			float intensity = (flowNoise(freq, kts) + rngm).toLinear;
			res += intensity;
			if (m_listenDirValid)
				s_stageIspec.bins[freq - 1] += intensity * m_flowNoiseMult;
		}
		res *= m_flowNoiseMult / (m_maxFreq + 1);
		m_baseFlowNoise = Intensity(res * m_directivity);
	}

	private void resetStageIspec()
	{
		s_stageIspec.bins.length = m_maxFreq;
		s_stageIspec.bins[] = Intensity(0.0f);
	}

	private void resetCurTds()
	{
		m_curTds.zeroOut(m_srate, m_srate);
	}

	/// transform current contents of s_stageIspec to time-domain and add
	/// the resulting signal to m_curTds
	private void applyStageIspec()
	{
		s_stageIspec.genSpectrum(s_stageSpectrum);
		ensureTlsCache();
		s_stageSpectrum.toTimeDomain(s_fftCache, s_stageTds);
		foreach (i, ref s; m_curTds.samples)
			s += s_stageTds.samples[i];
		resetStageIspec();
	}

	/// ditto
	private void applyStageIspec(const(IModulator) mod, float powerPart = 1.0f)
	{
		s_stageIspec.genSpectrum(s_stageSpectrum);
		float linGain = sqrt(powerPart);
		foreach (ref bin; s_stageSpectrum.bins)
			bin *= linGain;
		ensureTlsCache();
		s_stageSpectrum.toTimeDomain(s_fftCache, s_stageTds);
		if (mod)
			mod.modulate(s_stageTds);
		foreach (i, ref s; m_curTds.samples)
			s += s_stageTds.samples[i];
		resetStageIspec();
	}

	/// apply directivity to s_stageSpectrum
	private void stageDirectivity()
	{
		foreach (ref bin; s_stageSpectrum.bins)
			bin *= m_directivity;
	}

	/// reset antennaes and apply isotropic noises
	void resetAndIsotropic(float kts)
	{
		if (m_hasListener)
		{
			m_prevTds.samplingRate = m_curTds.samplingRate;
			m_prevTds.samples = m_curTds.samples.dup;
			resetCurTds();
			resetStageIspec();
			updateListenCell();
		}
		else
			m_prevTds.samples.length = 0;
		updateSeaIntensity();
		updateFlowNoise(kts);
		if (m_listenDirValid)
		{
			stageDirectivity();
			applyStageIspec();
			// water and flow noises now reach m_curTds
		}
		foreach (a; m_ant)
		{
			a.reset();
			a.applyIsotropic();
		}
	}

	// precalculated data
	private struct SourcePrecalc
	{
		vec2d dir;
		double range;
		double worldBearing;
		float haloBase;
		float haloBound;
	}

	private SourcePrecalc precalcForSource(SoundSource s)
	{
		SourcePrecalc res;
		res.dir = s.transform.wposition - m_transform.wposition;
		res.range = res.dir.length;
		res.worldBearing = courseAngle(res.dir) +
			uniform(-m_bearingErrNoise, m_bearingErrNoise);
		// half of halo size
		res.haloBase = s.radius / res.range + pointHaloAngle(res.range);
		res.haloBound = fmin(3.0 * res.haloBase, MAX_HALO);
		return res;
	}

	void applySoundSource(SoundSource s)
	{
		SourcePrecalc prec = precalcForSource(s);
		foreach (a; m_ant)
			a.applySoundSource(s, prec);
	}

	immutable(ushort)[] getBroadbandData(int antennaIdx) const
	{
		ushort[] res;
		m_ant[antennaIdx].imprint(res);
		return cast(immutable(ushort)[]) res;
	}

	/// Continuous block of hydrophone elements
	private final class Antennae
	{
		this(int cellCount, float mainAxisRot)
		{
			assert(cellCount > 0);
			rot = mainAxisRot;
			cells.length = cellCount;
			cell0Left = m_span / 2;
		}

		private
		{
			Intensity[] cells;
			float rot;	// rotation relative to hydrophone transform
			// index of listening cell. If negative, no cell is negative
			int listenCell = -1;
			// relative bearing of left edge of first cell from the left
			float cell0Left;
		}

		/// reset cells array to zero energies
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
			foreach (i, const c; cells)
			{
				dest[i] = IntensityLevel(c.toDb + uniform(0.0f, m_baseNoise));
				assert(!isNaN(dest[i].val));
			}
		}

		void imprint(ref ushort[] dest, dB maxLevel = 90.0f) const
		{
			dest.length = cells.length;
			foreach (i, const c; cells)
			{
				float level = max(0.0f, IntensityLevel(c.toDb + uniform(0.0f, m_baseNoise)));
				assert(!isNaN(level));
				dest[i] = lrint(
					min(float(ushort.max), level / maxLevel * ushort.max)).to!ushort;
			}
		}

		int relBearingToCell(double relBearing)
		{
			return floor((cell0Left - relBearing) / m_cellAngle).to!int;
		}

		void applySoundSource(SoundSource s, SourcePrecalc p)
		{
			double relBearing = clampAnglePi(
				p.worldBearing - m_transform.wrotation - rot);
			// first cell we'll add energy to
			int cellStart = relBearingToCell(relBearing + p.haloBound);
			// last cell we'll add energy to
			int cellEnd = relBearingToCell(relBearing - p.haloBound);
			// check if we actually intersect
			if (cellStart >= cells.length || cellEnd < 0)
				return;
			cellStart = max(0, cellStart);
			cellEnd = min(cells.length - 1, cellEnd);
			bool needModulator = cellStart <= listenCell && cellEnd >= listenCell;

			void onBuilt(const IModulator mod)
			{
				float bandSum = s_stageIspec.bins.sum() / (m_maxFreq + 1);
				for (int ci = cellStart; ci <= cellEnd; ci++)
				{
					float cellLeft = cell0Left - ci * m_cellAngle;
					float cellRight = cellLeft - m_cellAngle;
					float normLeft = (relBearing - cellLeft) / p.haloBase;
					float normRight = (relBearing - cellRight) / p.haloBase;
					assert(normRight >= normLeft);
					float powerPart = 0.5 * (erf(normRight) - erf(normLeft));
					cells[ci] += bandSum * powerPart;
					if (m_listenDirValid && listenCell == ci)
						applyStageIspec(mod, powerPart);
				}
			}

			s.getIntensitySpectrum(m_transform.wposition, s_stageIspec,
				&onBuilt, m_minFreq, m_maxFreq, m_listenDirValid && needModulator, 4.0f);
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
		[0.0f],
		500, 2047, dgr2rad(180.0f), 181, 4 / 181.0f, 3.0f, 0.001f, 0.001f);
	Hydrophone h = new Hydrophone(new Transform2D(), hp);
	IntensityLevel[][] ilevels;
	ilevels.length = 90;
	float spdKts = 0.0f;
	float spdStep = 17.0f * 3.6 / 2 / ilevels.length;
	for (size_t i = 0; i < ilevels.length; i++)
	{
		h.resetAndIsotropic(spdKts);
		h.m_ant[0].imprint(ilevels[i]);
		spdKts += spdStep;
	}
	printToPng("std_hydrophone_0-17ms.png", ilevels, 0.0f, 90.0f);
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
		[0.0f],
		500, 2047, dgr2rad(210.0f), 210, 2.0 / 90.0f, 3.0f, 0.002f, 0.001f);
	Hydrophone h = new Hydrophone(new Transform2D(), hp);
	IntensityLevel[][] ilevels;
	ilevels.length = 200;
	float spdKts = 0.0f;
	for (size_t i = 0; i < ilevels.length; i++)
	{
		h.resetAndIsotropic(spdKts);
		foreach (j, float spd; speeds)
		{
			float freq = spd * freqPerMs;
			prop.preUpdate(freq, spd);
			prop.postUpdate(freq, spd, 1.0f);
			propTrans.position = rotateVector(vec2d(0.0, (i + 1) * 150.0), relBearings[j]);
			h.applySoundSource(prop);
		}
		h.m_ant[0].imprint(ilevels[i]);
	}
	printToPng("std_hydrophone_vs_std_propeller_30km.png", ilevels, 0.0f, 90.0f);

	// generate sound sample of std_propeller on 1km range
	propTrans.position = vec2d(0.0, 1000.0);
	h.hasListener = true;
	h.listenDir = 0.0;
	float spd = 15.0f;
	float freq = spd * freqPerMs;
	writeln("fundamental shaft frequency = ", freq);
	prop.preUpdate(freq, spd);
	prop.postUpdate(freq, spd, 1.0f);

	TimeDomainSignal tds;
	for (int i = 0; i < 1; i++)
	{
		h.resetAndIsotropic(mpsToKts(0));
		assert(h.m_listenDirValid);
		assert(h.m_ant[0].listenCell >= 0);
		h.applySoundSource(prop);
		const(TimeDomainSignal) tds1 = h.finalizeListenTds();
		tds.samplingRate = tds1.samplingRate;
		tds.samples ~= tds1.samples;
	}
	float maxp = tds.samples.map!(a => a.re).maxElement;
	writeln("std_hydrophone_vs_std_propeller_1km maxp: ", maxp);
	writeWavFile("std_hydrophone_vs_std_propeller_1km.wav",
		tds.samples.cycle.take(6 * 4096),
		0.8f / maxp, tds.samplingRate);
}