module dsubs_sound.hydrophone;

import std.algorithm.comparison: min, max;
import std.algorithm.iteration: sum;
import std.array: array;
import std.range;
import std.stdio;

import dsubs_common.math;
import dsubs_common.event;
import dsubs_common.api.entities;

import dsubs_sound.common;
import dsubs_sound.spectrum;
import dsubs_sound.filter;
import dsubs_sound.water;
import dsubs_sound.soundsource;
import dsubs_sound.modulation;


struct HydrophonePrototype
{
	float[] antennaeRots;
	int minFreq, maxFreq;
	float antennaeSpan;
	int beamCount;
	float directivity;
	dB baseNoise = 3.0f;
	float bearingErrNoise = 0.001f;
	float flowNoiseMult = 0.001f;
	float selfNoiseMult = 1e-3f;
	float listenSpan = dgr2rad(2);
}


/// Hydrophone is a collection of identical antennaes
final class Hydrophone
{
	this(Transform2D t, ref const HydrophonePrototype p)
	{
		assert(p.minFreq >= 20 && p.maxFreq >= p.minFreq);
		m_transform = t;
		m_minFreq = p.minFreq;
		m_tdsFilter = highpass500;
		m_maxFreq = p.maxFreq;
		m_srate = m_maxFreq * 2;
		m_directivity = p.directivity;
		m_baseNoise = p.baseNoise;
		m_span = p.antennaeSpan;
		m_listenSpan = p.listenSpan;
		m_bearingErrNoise = p.bearingErrNoise;
		m_flowNoiseMult = p.flowNoiseMult;
		m_selfNoiseMult = p.selfNoiseMult;
		assert(m_span > 0.0f && m_span < 2 * PI - MAX_HALO);
		assert(p.beamCount > 0);
		m_beamAngle = m_span / p.beamCount;
		m_listenToCellR = m_listenSpan / m_beamAngle;
		foreach (rot; p.antennaeRots)
			m_ant ~= new Antennae(p.beamCount, rot);
		m_iinterp = new IntensityInterpolator();
		onPreSimulation += &savePrevPos;
		savePrevPos();
	}

	/// invoked by simulator before kinematic update happens
	Event!(void delegate()) onPreSimulation;
	/// invoked by simulator right after kinematic update happens
	Event!(void delegate()) onPostSimulation;

	private
	{
		Transform2D m_transform;
		vec2d m_prevPos;
		double m_prevRot;
		Antennae[] m_ant;
		immutable LinearFIR m_tdsFilter;
		int m_minFreq, m_maxFreq, m_srate;
		float m_span;
		float m_beamAngle;
		float m_listenSpan;
		float m_listenToCellR;
		float m_directivity;
		float m_bearingErrNoise;
		float m_flowNoiseMult;
		float m_selfNoiseMult;
		dB m_baseNoise;

		/// speed in knots at the start of integration
		float m_ktsStart = 0.0f;
		float m_ktsEnd = 0.0f;
		IntensityInterpolator m_iinterp;

		enum float MAX_HALO = dgr2rad(20);
		enum float MAX_HALO_2 = MAX_HALO / 2;
		enum float HALO_GAIN = 3.0f;
		enum float ISOTROPIC_VAR = 2.0;
		enum int MIN_FREQ = 20;
		enum float LOCAL_NOISE_RANGE = 100.0f;

		// broadband sea background noise intensity
		Intensity m_baseSeaNoise;
		// broadband flow noise intensity
		Intensity m_baseFlowNoise;

		// true when the player is listening signals from this hydrophone
		bool m_hasListener;
		// world-space direction the player is listening to
		float m_listenDir = 0.0f;
		// false when no active antenna has a beam for chosen listen Dir
		bool m_listenDirValid;

		// unfiltered time domain signals that are generated for listening player
		TimeDomainSignal m_prevTds;
		TimeDomainSignal m_curTds;
	}

	/// save current position of transform to m_prevPos
	private void savePrevPos()
	{
		m_prevPos = m_transform.wposition;
		m_prevRot = m_transform.wrotation;
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

	/// finalize m_curTds by overlapping it with m_prevTds
	const(TimeDomainSignal) finalizeListenTds()
	{
		assert(m_listenDirValid);
		// if (m_prevTds.samples.length)
		// 	overlapTDS(m_prevTds, m_curTds, m_srate / 8);
		s_stageTds.samplingRate = m_srate;
		s_stageTds.samples.length = m_srate;
		m_tdsFilter.filter(chain(m_curTds.samples, m_prevTds.samples).cycled,
			s_stageTds.samples);
		// m_tdsFilter.filter(m_prevTds.samples ~ m_curTds.samples,
		// 	s_stageTds.samples, m_srate);
		return s_stageTds;
	}

	immutable(short)[] finalizePcbData(out int srate, float maxp = 1e5)
	{
		const(TimeDomainSignal) tds = finalizeListenTds();
		srate = tds.samplingRate;
		short[] res = new short[tds.samples.length];
		for (size_t i = 0; i < res.length; i++)
			res[i] = (fmax(-1.0f, fmin(1.0f, tds.samples[i] / maxp)) * short.max).to!short;
		return cast(immutable(short)[]) res;
	}

	// recalculate listening beam according to current transform rotation
	private void updateListenCell()
	{
		m_listenDirValid = false;
		foreach (ant; m_ant)
		{
			if (m_listenDirValid)
			{
				ant.listenCell = false;
				continue;
			}
			double relBearing = clampAnglePi(
				m_listenDir - m_transform.wrotation - ant.rot);
			bool belongs = (relBearing <= m_span / 2) && (relBearing >= -m_span / 2);
			if (belongs)
			{
				m_listenDirValid = true;
				ant.listenCell = true;
			}
			else
				ant.listenCell = false;
		}
	}

	private void applySeaNoise()
	{
		float res = 0;
		for (int freq = m_minFreq; freq < m_maxFreq; freq++)
		{
			float rngm = uniform(-ISOTROPIC_VAR, ISOTROPIC_VAR);
			float intensity = (seaNoiseIL(freq) + rngm).toLinear;
			if (m_listenDirValid)
				s_stageIspec.bins[freq] = intensity * m_directivity * m_listenToCellR;
			res += intensity;
		}
		res /= m_maxFreq;
		m_baseSeaNoise = Intensity(res * m_directivity);
		if (m_listenDirValid)
			applyStageIspec();
	}

	private void applyFlowNoise()
	{
		float resStart = 0.0f;
		float resEnd = 0.0f;
		float ktsStartAbs = m_ktsStart.abs;
		float ktsEndAbs = m_ktsEnd.abs;
		for (int freq = m_minFreq; freq < m_maxFreq; freq++)
		{
			float rngm = uniform(-ISOTROPIC_VAR, ISOTROPIC_VAR);
			float intensityStart = (flowNoise(freq, ktsStartAbs) + rngm).toLinear;
			float intensityEnd = (flowNoise(freq, ktsEndAbs) + rngm).toLinear;
			float iavg = 0.5f * (intensityStart + intensityEnd);
			if (m_listenDirValid)
				s_stageIspec.bins[freq] = iavg * m_flowNoiseMult *
					m_directivity * m_listenToCellR;
			resStart += intensityStart;
			resEnd += intensityEnd;
		}
		float mult = m_flowNoiseMult / m_maxFreq;
		resStart *= mult;
		resEnd *= mult;
		float resAvg = 0.5f * (resStart + resEnd);
		m_baseFlowNoise = Intensity(resAvg * m_directivity);
		if (m_listenDirValid && resAvg != 0.0f)
		{
			m_iinterp.startIntensityMult = resStart * sgn(m_ktsStart) / resAvg;
			m_iinterp.endIntensityMult = resEnd * sgn(m_ktsEnd) / resAvg;
			applyStageIspec(m_iinterp);
		}
	}

	private void resetStageIspec()
	{
		s_stageIspec.bins.length = m_maxFreq + 1;
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
		m_curTds.samples[] += s_stageTds.samples[];
		resetStageIspec();
	}

	/// ditto
	private void applyStageIspec(const IModulator mod, float powerPart = 1.0f)
	{
		for (size_t i = 0; i < s_stageIspec.bins.length; i++)
			s_stageIspec.bins[i] *= powerPart;
		s_stageIspec.genSpectrum(s_stageSpectrum);
		ensureTlsCache();
		s_stageSpectrum.toTimeDomain(s_fftCache, s_stageTds);
		if (mod)
			mod.modulate(s_stageTds);
		m_curTds.samples[] += s_stageTds.samples[];
		resetStageIspec();
	}

	/// modulate tds and add it to m_curTds
	private void applyTdsAdditive(TimeDomainSignal tds, const IModulator mod)
	{
		if (mod)
			mod.modulate(tds);
		m_curTds.samples[] += tds.samples[];
	}

	/// set speed at the start of integration
	@property float ktsStart(float rhs)
	{
		return m_ktsStart = rhs;
	}

	/// set speed at the end of integration
	@property float ktsEnd(float rhs)
	{
		return m_ktsEnd = rhs;
	}

	private void swapTdses()
	{
		if (m_prevTds.samples.length == 0)
		{
			m_prevTds.samplingRate = m_curTds.samplingRate;
			m_prevTds.samples.length = m_curTds.samples.length;
		}
		auto prev = m_prevTds.samples;
		m_prevTds.samples = m_curTds.samples;
		m_curTds.samples = prev;
	}

	/// reset antennaes and apply isotropic noises (sea and flow)
	void resetAndIsotropic()
	{
		if (m_hasListener)
		{
			swapTdses();
			resetCurTds();
			resetStageIspec();
			updateListenCell();
		}
		else
			m_prevTds.samples.length = 0;
		applySeaNoise();
		applyFlowNoise();
		foreach (a; m_ant)
		{
			a.reset();
			a.applyIsotropic();
		}
	}

	// precalculated data
	private struct SourcePrecalc
	{
		vec2d dirEnd;
		vec2d dirStart;
		double range;
		double worldBearingStart;
		double worldBearingEnd;
		float haloBase;
		float haloBound;
	}

	private SourcePrecalc precalcForSource(SoundSource s)
	{
		SourcePrecalc res;
		res.dirStart = s.prevPos - m_prevPos;
		res.dirEnd = s.position - m_transform.wposition;
		res.range = max(5.0, res.dirEnd.length);
		assert(res.range > 0.0);
		res.worldBearingStart = courseAngle(res.dirStart);
		res.worldBearingEnd = courseAngle(res.dirEnd);
		// half of halo size
		res.haloBase = (s.radius / res.range + pointHaloAngle(res.range)) * (1 + uniform(-0.06f, 0.06f));
		res.haloBound = fmin(HALO_GAIN * res.haloBase, MAX_HALO);
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
		this(int beamCount, float mainAxisRot)
		{
			assert(beamCount > 0);
			rot = mainAxisRot;
			beams.length = beamCount;
			beam0Left = m_span / 2;
		}

		private
		{
			Intensity[] beams;
			float rot;	// rotation relative to hydrophone transform
			// true if listenDir belongs to this antenna
			bool listenCell;
			// relative bearing of left edge of first beam from the left
			float beam0Left;
		}

		/// reset beams array to zero energies
		void reset()
		{
			foreach (ref c; beams)
				c = Intensity(0.0f);
		}

		/// apply backround sea noise and flow noises
		void applyIsotropic()
		{
			foreach (ref c; beams)
				c += m_baseSeaNoise + m_baseFlowNoise;
		}

		/// sample beams random distribution and convert to intensity levels
		void imprint(ref IntensityLevel[] dest) const
		{
			dest.length = beams.length;
			foreach (i, const c; beams)
			{
				dest[i] = IntensityLevel(c.toDb + uniform(0.0f, m_baseNoise));
				assert(!isNaN(dest[i].val));
			}
		}

		void imprint(ref ushort[] dest, dB maxLevel = 90.0f) const
		{
			dest.length = beams.length;
			foreach (i, const c; beams)
			{
				float level = max(0.0f, IntensityLevel(c.toDb + uniform(0.0f, m_baseNoise)));
				assert(!isNaN(level));
				dest[i] = lrint(
					min(float(ushort.max), level / maxLevel * ushort.max)).to!ushort;
			}
		}

		int relBearingToCell(double relBearing)
		{
			return floor((beam0Left - relBearing) / m_beamAngle).lrint.to!int;
		}

		int sectorNormToCell(float norm)
		{
			return max(0, min(beams.length - 1, floor(norm * beams.length).lrint)).to!int;
		}

		struct PowerIntegr
		{
			float totalPart = 0.0f;
			float startPart;
			float endPart;
		}

		static PowerIntegr integrateBetweenBeams(float left, float right,
			float brngStart, float brngEnd, float halo, int integrPoints = 2)
		{
			assert(integrPoints >= 1);
			assert(right <= left);
			halo *= HALO_GAIN;
			float relBearing = brngStart;
			PowerIntegr res;
			float drx = angleDist(brngEnd, brngStart) / (integrPoints - 1);
			Sector beamSector = Sector(left, right);
			for (int i = 0; i < integrPoints; i++)
			{
				SectorProjection sp = projectSectorsIntersect(beamSector,
					Sector(relBearing + halo, relBearing - halo));
				assert(sp.count < 2);
				float part = 0.0f;
				if (sp.count == 1)
				{
					float normLeft = (sp.proj[0].left - 0.5f) * 2 * HALO_GAIN;
					float normRight = (sp.proj[0].right - 0.5f) * 2 * HALO_GAIN;
					assert(normRight >= normLeft);
					part = 0.5f * (erf(normRight) - erf(normLeft));
					assert(part >= 0.0f);
					res.totalPart += part;
				}
				if (i == 0)
					res.startPart = part;
				else if (i == integrPoints - 1)
					res.endPart = part;
				relBearing += drx;
			}
			res.totalPart /= integrPoints;
			assert(!isNaN(res.totalPart));
			return res;
		}

		void applySoundSource(SoundSource s, SourcePrecalc p)
		{
			float bearingErr = uniform(-m_bearingErrNoise, m_bearingErrNoise);
			double relBearing1 = clampAnglePi(
				p.worldBearingStart + bearingErr - m_prevRot - rot);
			double relBearing2 = clampAnglePi(
				p.worldBearingEnd + bearingErr - m_transform.wrotation - rot);

			Sector allCellsSect = Sector(beam0Left, -beam0Left);
			SectorProjection sectProj1 = projectSectorsIntersect(
				Sector(relBearing1 + p.haloBound, relBearing1 - p.haloBound), allCellsSect);
			assert(sectProj1.count < 2);
			SectorProjection sectProj2 = projectSectorsIntersect(
				Sector(relBearing2 + p.haloBound, relBearing2 - p.haloBound), allCellsSect);
			assert(sectProj2.count < 2);

			bool localSource = p.range <= LOCAL_NOISE_RANGE;
			bool isSelfNoise;
			if (sectProj1.count == 0 && sectProj2.count == 0)
			{
				if (localSource)
					isSelfNoise = true;
				else
					return;
			}
			// first beam we'll add energy to
			int beamStart = beams.length.to!int;
			int beamEnd = -1;
			if (sectProj1.count)
			{
				beamStart = min(beamStart, sectorNormToCell(sectProj1.proj[0].left));
				beamEnd = max(beamEnd, sectorNormToCell(sectProj1.proj[0].right));
			}
			if (sectProj2.count)
			{
				beamStart = min(beamStart, sectorNormToCell(sectProj2.proj[0].left));
				beamEnd = max(beamEnd, sectorNormToCell(sectProj2.proj[0].right));
			}

			bool needTds = listenCell;

			void onBuilt(float bandSum, TimeDomainSignal tds)
			{
				if (isSelfNoise)
				{
					float mult = m_directivity * m_selfNoiseMult;
					foreach (ref beam; beams)
						beam += bandSum * mult;
					if (needTds)
					{
						m_iinterp.startIntensityMult = mult;
						m_iinterp.endIntensityMult = mult;
						applyTdsAdditive(tds, m_iinterp);
					}
				}
				else
				{
					// apply broadband power to beams
					for (int ci = beamStart; ci <= beamEnd; ci++)
					{
						float beamLeft = beam0Left - ci * m_beamAngle;
						float beamRight = beamLeft - m_beamAngle;
						float powerPart = integrateBetweenBeams(beamLeft, beamRight,
							relBearing1, relBearing2, p.haloBase, 3).totalPart;
						beams[ci] += bandSum * powerPart;
					}

					// apply time-domain stuff
					if (needTds)
					{
						float left = m_listenDir + m_listenSpan / 2;
						float right = m_listenDir - m_listenSpan / 2;
						PowerIntegr integr = integrateBetweenBeams(left, right,
							p.worldBearingStart, p.worldBearingEnd, p.haloBase);
						if (integr.totalPart != 0.0f)
						{
							m_iinterp.startIntensityMult = integr.startPart;
							m_iinterp.endIntensityMult = integr.endPart;
							applyTdsAdditive(tds, m_iinterp);
						}
					}
				}
			}

			s.buildSignals(m_transform.wposition, &onBuilt, m_minFreq, m_maxFreq,
				m_listenDirValid && needTds, 4.0f);
		}
	}
}


import imageformats;

/// print passive sonar data to PNG image
private void printToPng(string filename, IntensityLevel[][] data, dB zeroLevel, dB maxLvl)
{
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
		500, 2048, dgr2rad(210.0f), 210, 2.0 / 90.0f, 3.0f, 4e-3, 2e-5);
	Hydrophone h = new Hydrophone(new Transform2D(), hp);
	h.transform.rotation = PI; // good corner case
	h.onPreSimulation();
	IntensityLevel[][] ilevels;
	ilevels.length = 200;
	float spdKts = mps2kts(0);
	h.ktsStart = h.ktsEnd = spdKts;
	for (size_t i = 0; i < ilevels.length; i++)
	{
		// h.onPreSimulation();
		// h.transform.rotation = i * dgr2rad(0.5);
		h.resetAndIsotropic();
		foreach (j, float spd; speeds)
		{
			float freq = spd * freqPerMs;
			propTrans.position = rotateVector(vec2d(0.0, (i + 1) * -150.0), relBearings[j]);
			prop.preUpdate(freq, spd);
			prop.postUpdate(freq, spd, 1.0f);
			h.applySoundSource(prop);
		}
		h.m_ant[0].imprint(ilevels[i]);
	}
	printToPng("std_hydrophone_vs_std_propeller_30km.png", ilevels, 0.0f, 90.0f);

	// test own speed vs detection capability
	float dspd = mps2kts(17) / ilevels.length;
	for (size_t i = 0; i < ilevels.length; i++)
	{
		h.ktsStart = h.ktsEnd = spdKts + dspd * i;
		h.resetAndIsotropic();
		foreach (j, float spd; speeds)
		{
			float freq = spd * freqPerMs;
			propTrans.position = rotateVector(vec2d(0.0, -5000.0), relBearings[j]);
			prop.preUpdate(freq, spd);
			prop.postUpdate(freq, spd, 1.0f);
			h.applySoundSource(prop);
		}
		h.m_ant[0].imprint(ilevels[i]);
	}
	printToPng("std_hydrophone_0-17ms.png", ilevels, 0.0f, 90.0f);

	// generate sound sample of std_propeller on 1km range
	propTrans.position = vec2d(0.0, -1000.0).rotateVector(dgr2rad(3));
	h.hasListener = true;
	h.listenDir = PI;
	float spd = 15.0f;
	float freq = spd * freqPerMs;
	writeln("fundamental shaft frequency = ", freq);
	h.ktsStart = h.ktsEnd = mps2kts(0);

	TimeDomainSignal tds;
	for (int i = 0; i < 8; i++)
	{
		prop.preUpdate(freq, spd);
		propTrans.position = vec2d(0.0, -1000.0).rotateVector(
			dgr2rad(3) - (i + 1) * dgr2rad(6.0f / 8));
		prop.postUpdate(freq, spd, 1.0f);
		h.resetAndIsotropic();
		assert(h.m_listenDirValid);
		assert(h.m_ant[0].listenCell >= 0);
		h.applySoundSource(prop);
		const(TimeDomainSignal) tds1 = h.finalizeListenTds();
		assert(tds1.samples.length == 4096);
		tds.samplingRate = tds1.samplingRate;
		tds.samples ~= tds1.samples;
		//tds.samples ~= repeat(Complex!float(0.0f, 0.0f)).take(128).array;
	}
	float maxp = tds.samples.map!(a => a.abs).maxElement;
	writeln("std_hydrophone_vs_std_propeller_1km maxp: ", maxp);
	writeWavFile("std_hydrophone_vs_std_propeller_1km.wav",
		tds.samples, 0.8f / maxp, tds.samplingRate);
}