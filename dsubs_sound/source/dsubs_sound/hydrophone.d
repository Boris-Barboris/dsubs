module dsubs_sound.hydrophone;

import std.algorithm.comparison: min, max;
import std.algorithm.iteration: sum;
import std.array: array;
import std.range;
import std.mathspecial;

import dsubs_common.math;
import dsubs_common.event;
import dsubs_common.containers.circqueue;

import dsubs_sound.common;
import dsubs_sound.spectrum;
import dsubs_sound.opencl;
import dsubs_sound.filter;
import dsubs_sound.water;
import dsubs_sound.soundsource;
import dsubs_sound.modulation;


struct HydrophonePrototype
{
	/// antennae rotations, relative to hydrophone transform
	float[] antennaeRots;
	/// frequency passband
	int minFreq, maxFreq;
	/// each antennae spans the sector of this size
	float antennaeSpan;
	/// number of beams, formed by each antennae
	int beamCount;
	float directivity;
	dB baseNoise = 3.0f;
	float bearingErrNoise = 4e-3f;
	float flowNoiseMult = 1.8e-5f;
	float omniNoiseMult = 0.025f;
	/// client listens to beam of this size
	float listenSpan = dgr2rad(3);
	/// water dissipation modifier
	float dissMod = 4.0f;
}


/// Hydrophone is a collection of identical antennaes.
final class Hydrophone
{
	this(CommandQueue q, Transform2D t, ref const HydrophonePrototype p)
	{
		assert(p.minFreq >= 20 && p.maxFreq >= p.minFreq && p.maxFreq <= GLOBAL_SRATE);
		m_transform = t;
		m_minFreq = p.minFreq;
		m_tdsFilter = q.ctx.getFilter("octaveHp" ~ m_minFreq.to!string);
		m_maxFreq = p.maxFreq;
		assert(m_maxFreq <= GLOBAL_SRATE / 2);
		m_directivity = p.directivity;
		m_baseNoise = p.baseNoise;
		m_dissMod = p.dissMod;
		m_span = p.antennaeSpan;
		m_listenSpan = p.listenSpan;
		m_bearingErrNoise = p.bearingErrNoise;
		m_flowNoiseMult = p.flowNoiseMult;
		m_omniNoiseMult = p.omniNoiseMult;
		assert(m_span > 0.0f && m_span < 2 * PI - MAX_HALO);
		assert(p.beamCount > 0);
		m_beamAngle = m_span / p.beamCount;
		m_listenToCellR = m_listenSpan / m_beamAngle;
		m_sourceQueue = CircQueue!SourcePrecalc(16);
		foreach (rot; p.antennaeRots)
			m_ant ~= new Antennae(p.beamCount, rot);
		onPreSimulation += &savePrevPos;
		savePrevPos();

		synchronized(q)
		{
			m_prevTds = Tds(q, 0.0f);
			m_curTds = Tds(q, 0.0f);
		}
		m_baseSeaNoiseBuf = Buffer(q.ctx, float.sizeof);
		m_baseFlowNoiseStartBuf = Buffer(q.ctx, float.sizeof);
		m_baseFlowNoiseEndBuf = Buffer(q.ctx, float.sizeof);
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
		FIRFilter* m_tdsFilter;
		int m_minFreq, m_maxFreq;
		float m_span;
		float m_beamAngle;
		float m_listenSpan;
		float m_listenToCellR;
		float m_directivity;
		float m_bearingErrNoise;
		float m_flowNoiseMult;
		float m_omniNoiseMult;
		float m_dissMod;
		dB m_baseNoise;

		/// speed in knots at the start of integration
		float m_ktsStart = 0.0f;
		float m_ktsEnd = 0.0f;

		enum float MAX_HALO = dgr2rad(20);
		enum float HALO_GAIN = 1.25f;
		enum float SOUND_HALO_GAIN = 1.5f;
		enum float ERF_HALO_GAIN = 2.0f;
		enum float ISOTROPIC_VAR = 2.0;
		enum float LOCAL_NOISE_RANGE_FULL = 10.0f;
		enum float LOCAL_NOISE_RANGE_CUTOFF = 200.0f;

		// broadband sea background noise intensity
		Intensity m_baseSeaNoise;
		Buffer m_baseSeaNoiseBuf;
		// broadband flow noise intensity
		Intensity m_baseFlowNoiseStart;
		Intensity m_baseFlowNoiseEnd;
		Buffer m_baseFlowNoiseStartBuf;
		Buffer m_baseFlowNoiseEndBuf;
		AsyncEvent m_isotropicReadyEvt;

		// when false, no calculations should be performed
		bool m_active = true;
		// world-space direction the player is listening to
		float m_listenDir = 0.0f;
		// false when no active antenna has a beam for chosen listen Dir
		bool m_listenDirValid;
		bool m_needPrevReset;

		// sound signals that are generated for actively-listening player
		Tds m_prevTds;
		Tds m_curTds;

		// we will copy resulting tds asynchronously from OpenCL devices
		short[GLOBAL_SRATE] m_pcb;
		AsyncEvent m_pcbEvt;
	}

	/// release underlying opencl buffers
	void release() nothrow @nogc
	{
		m_baseSeaNoiseBuf.release();
		m_baseFlowNoiseStartBuf.release();
		m_baseFlowNoiseEndBuf.release();
		m_prevTds.release();
		m_curTds.release();
	}

	/// save current position of transform to m_prevPos
	private void savePrevPos()
	{
		m_prevPos = m_transform.wposition;
		m_prevRot = m_transform.wrotation;
	}

	@property Transform2D transform() { return m_transform; }

	@property bool active() const { return m_active; }

	@property bool listenDirValid() const { return m_listenDirValid; }

	@property size_t antennaCount() const { return m_ant.length; }

	@property void active(bool rhs)
	{
		if (!m_active && rhs)
			m_needPrevReset = true;
		m_active = rhs;
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

	/// finalize m_curTds by filtering it
	private void finalizeListenTds(CommandQueue q)
	{
		assert(m_listenDirValid);
		m_tdsFilter.filter(q, m_prevTds, m_curTds, q.s_tds);
	}

	/// Starts converting m_curTds to short Pcb samples and enqueue asynchronous read
	/// to m_pcb short buffer
	void startFinalizePcbData(CommandQueue q, float maxp)
	{
		finalizeListenTds(q);
		Kernel k = q.mk_toShortPcb;
		k.setArg(0, q.s_tds.mem);
		k.setArg(1, q.s_pcbBuf.mem);
		k.setArg(2, maxp);
		k.enqueue(q, 1, null, [GLOBAL_SRATE], null, null);
		m_pcbEvt = q.s_pcbBuf.enqueueFullRead(q, m_pcb.ptr, null);
	}

	/// Wait for opencl to copy converted m_curTds into ram
	void endFinalizePcbData()
	{
		waitFor(m_pcbEvt);
	}

	@property immutable(short)[] pcb() { return cast(immutable) m_pcb[]; }

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

	private void startCalculateSeaNoise(CommandQueue q)
	{
		// zero out intensities
		q.s_ispec.patch(q, 0.0f);
		// dispatch sea noise spectrum calculation
		Kernel k = q.mk_generateSeaNoise;
		k.setArg(0, q.s_ispec.mem);
		k.setArg(1, m_directivity * m_listenToCellR);
		k.setArg(2, ISOTROPIC_VAR);
		k.setArg(3, uintSeed());
		k.enqueue(q, 1, [m_minFreq - 1], [m_maxFreq - m_minFreq + 1], null, null);
		// s_ispec now contains sea noise spectrum, let's sum it
		q.s_ispec.reduceSum(q, m_baseSeaNoiseBuf, m_minFreq, m_maxFreq);
		// m_baseSeaNoiseBuf must contain sum of intensity bins
		// !!don't forget to scale it's value by m_listenToCellR!!
		m_baseSeaNoiseBuf.enqueueFullRead(q, &m_baseSeaNoise, null).release();
		// if we have an active listener, we need to apply sea noise to it
		if (m_listenDirValid)
		{
			q.s_ispec.toTimeDomain(q, q.s_tds);
			q.s_tds.addTo(q, m_curTds);
		}
	}

	private void startCalculateFlowNoise(CommandQueue q)
	{
		void dispatchFlowCalc(ref ISpectrum spec, float kts)
		{
			spec.patch(q, 0.0f);
			Kernel k = q.mk_generateFlowNoise;
			k.setArg(0, spec.mem);
			k.setArg(1, m_flowNoiseMult * m_directivity * m_listenToCellR);
			k.setArg(2, kts.abs);
			k.setArg(3, ISOTROPIC_VAR);
			k.setArg(4, uintSeed());
			k.enqueue(q, 1, [m_minFreq - 1],
				[m_maxFreq - m_minFreq + 1], null, null);
		}
		dispatchFlowCalc(q.s_ispec, m_ktsStart);
		dispatchFlowCalc(q.s_ispec2, m_ktsEnd);

		q.s_ispec.reduceSum(q, m_baseFlowNoiseStartBuf, m_minFreq, m_maxFreq);
		q.s_ispec2.reduceSum(q, m_baseFlowNoiseEndBuf, m_minFreq, m_maxFreq);
		// !!don't forget to scale it's value by m_listenToCellR!!
		m_baseFlowNoiseStartBuf.enqueueFullRead(q, &m_baseFlowNoiseStart, null).release();
		m_isotropicReadyEvt = m_baseFlowNoiseEndBuf.enqueueFullRead(q,
			&m_baseFlowNoiseEnd, null);
		// if we have an active listener, we need to apply flow noise to it
		if (m_listenDirValid)
		{
			q.s_ispec2.addTo(q, q.s_ispec);
			q.s_ispec.toTimeDomain(q, q.s_tds);
			Kernel k = q.mk_interpolateIntensity2;
			k.setArg(0, q.s_tds.mem);
			k.setArg(1, m_baseFlowNoiseStartBuf.mem);
			k.setArg(2, m_baseFlowNoiseEndBuf.mem);
			k.setArg(3, 0.5f * sgn(m_ktsStart));
			k.setArg(4, 0.5f * sgn(m_ktsEnd));
			k.enqueue(q, 1, null, [GLOBAL_SRATE], null, null);
			q.s_tds.addTo(q, m_curTds);
		}
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

	/// Reset antennaes and start calculating isotropic noises (sea and flow).
	/// You must call endIsotropic() to actually apply isotropic noises
	/// to antennae broadband beams.
	void resetAndStartIsotropic(CommandQueue q)
	{
		updateListenCell();
		if (m_listenDirValid)
		{
			m_curTds.swapWith(m_prevTds);
			m_curTds.fill(q, 0.0f);
			if (m_needPrevReset)
			{
				m_prevTds.fill(q, 0.0f);
				m_needPrevReset = false;
			}
		}
		startCalculateSeaNoise(q);
		startCalculateFlowNoise(q);
		foreach (a; m_ant)
			a.reset();
	}

	/// Call after resetAndStartIsotropic
	void endIsotropic()
	{
		m_isotropicReadyEvt.waitFor();
		foreach (a; m_ant)
			a.applyIsotropic();
	}

	private struct AntennaePrecalc
	{
		int beamStart;
		int beamEnd;
		double relBearing1;
		double relBearing2;
	}

	// precalculated sound source context
	private struct SourcePrecalc
	{
		vec2d dirEnd;
		vec2d dirStart;
		double rangeStart;
		double rangeEnd;
		double worldBearingStart;
		double worldBearingEnd;
		float haloBaseRadius;
		float haloBound;
		float omniFactorStart = 0.0f;
		float omniFactorEnd = 0.0f;

		alias range = rangeEnd;

		AntennaePrecalc[2] antPrec;

		enum int MAX_COMPONENTS = 2;
		Intensity[MAX_COMPONENTS] bandSum;	/// OpenCL writes here the sum of band intensities
		AsyncEvent[MAX_COMPONENTS] evt;		/// set when bandSum is ready
		int components = 0;
	}

	// Sound sources are enqueued and processed asynchronously by opencl.
	// In order to generate broadband beam data on cpu we await band sums,
	// calculated in opencl. That requires queuing in order to be efficient.
	private CircQueue!SourcePrecalc m_sourceQueue;

	private SourcePrecalc precalcForSource(SoundSource s)
	{
		SourcePrecalc res;
		res.dirStart = s.prevPos - m_prevPos;
		res.dirEnd = s.position - m_transform.wposition;
		res.rangeStart = max(10.0, res.dirStart.length);
		res.rangeEnd = max(10.0, res.dirEnd.length);
		res.omniFactorStart = max(s.minOmniFactor(res.rangeStart),
			caclOmniFactor(res.rangeStart));
		res.omniFactorEnd = max(s.minOmniFactor(res.rangeEnd),
			caclOmniFactor(res.rangeEnd));
		assert(res.range > 0.0);
		res.worldBearingStart = courseAngle(res.dirStart);
		res.worldBearingEnd = courseAngle(res.dirEnd);
		res.haloBaseRadius = (atan(s.radius / res.range) + pointHaloAngle(res.range)) *
			(1 + uniform(-0.06f, 0.06f));
		res.haloBound = fmin(HALO_GAIN * res.haloBaseRadius, MAX_HALO);
		return res;
	}

	private static float caclOmniFactor(float range)
	{
		if (range <= LOCAL_NOISE_RANGE_FULL)
			return 1.0f;
		float linGain = max(0.0f, 1.0f -
			(range - LOCAL_NOISE_RANGE_FULL) / LOCAL_NOISE_RANGE_CUTOFF);
		return pow(linGain, 2);
	}

	void applySoundSource(CommandQueue q, SoundSource s)
	{
		SourcePrecalc prec = precalcForSource(s);
		bool isVisible = prec.omniFactorStart > 0.0f || prec.omniFactorEnd > 0.0f;
		foreach (i, a; m_ant)
		{
			isVisible |= a.precalcForAntennae(i.to!int, prec);
		}
		if (!isVisible)
			return;
		// we need to make sure we have space in queue
		if (m_sourceQueue.capacity == m_sourceQueue.length)
		{
			//trace("hydrophone queue full, popping early");
			popSourceSignal();
		}
		// source is visible, let's issue sound rendering commands
		startSourceCalc(q, s, m_sourceQueue.pushBack(prec));
	}

	/// Process leftovers in source queue
	void flushSourceQueue()
	{
		while (m_sourceQueue.length > 0)
			popSourceSignal();
	}

	private void popSourceSignal()
	{
		int compCount = m_sourceQueue.front.components;
		assert(compCount > 0);
		//trace("popping with evt: ", m_sourceQueue.front.evt);
		for (int i = 0; i < compCount; i++)
		{
			AsyncEvent e = m_sourceQueue.front.evt[i];
			if (e != AsyncEvent.init)
				e.waitFor();
		}
		foreach (i, a; m_ant)
			a.applyBuiltIntensity(i.to!int, m_sourceQueue.front);
		m_sourceQueue.popFront();
	}

	private void startSourceCalc(CommandQueue q, SoundSource s, ref SourcePrecalc p)
	{
		bool needTds = m_listenDirValid;

		PowerIntegr integr;
		if (m_listenDirValid)
		{
			float left = m_listenDir + m_listenSpan / 2;
			float right = m_listenDir - m_listenSpan / 2;
			integr = integrateBetweenBeams(left, right,
				p.worldBearingStart, p.worldBearingEnd, p.haloBound * SOUND_HALO_GAIN);
		}
		if (needTds && integr.totalPart == 0.0f && p.omniFactorStart == 0.0f &&
			p.omniFactorEnd == 0.0f)
		{
			needTds = false;
		}

		void onTdsReady(Intensity* bandIntSum, Buffer* bandIntensitySumBuf, Tds* tds)
		{
			assert(p.components < p.MAX_COMPONENTS);
			if (bandIntSum != null)
			{
				// band intensity sum is already calculated on the CPU
				p.bandSum[p.components] = *bandIntSum;
			}
			else
			{
				// band intensity sum will arrive later from OpenCL
				assert(bandIntensitySumBuf !is null);
				AsyncEvent evt = bandIntensitySumBuf.enqueueFullRead(q,
					&p.bandSum[p.components], null);
				p.evt[p.components] = evt;
			}
			if (needTds && tds)
			{
				float omniImultStart = p.omniFactorStart * m_directivity * m_omniNoiseMult;
				float omniImultEnd = p.omniFactorEnd * m_directivity * m_omniNoiseMult;
				dB intensStart = max(-60.0f, toDb(
					omniImultStart + (1.0f - omniImultStart) * integr.startPart));
				assert(intensStart <= 0.0f);
				dB intensEnd = max(-60.0f, toDb(
					omniImultEnd + (1.0f - omniImultEnd) * integr.endPart));
				assert(intensEnd <= 0.0f);
				modulateILevelInterp(q, *tds, intensStart, intensEnd);
				tds.addTo(q, m_curTds);
			}
			p.components++;
		}

		s.buildSignals(q, m_transform.wposition, &onTdsReady, m_minFreq,
			m_maxFreq, needTds, m_dissMod, m_tdsFilter);
	}

	private struct PowerIntegr
	{
		float totalPart = 0.0f;
		float startPart;
		float endPart;
	}

	private static PowerIntegr integrateBetweenBeams(float left, float right,
		float brngStart, float brngEnd, float haloRadius, int integrPoints = 13)
	{
		assert(integrPoints >= 2);
		assert(right <= left);
		PowerIntegr res;
		float drx = angleDist(brngEnd, brngStart) / (integrPoints - 1);
		float relBearing = brngStart;
		Sector beamSector = Sector(left, right);
		for (int i = 0; i < integrPoints; i++)
		{
			SectorIntersection sp = projectSectorsIntersect(beamSector,
				Sector(relBearing + haloRadius, relBearing - haloRadius));
			assert(sp.count < 2);
			float part = 0.0f;
			if (sp.count == 1)
			{
				float normLeft = (sp.proj[0].left - 0.5f) * 2 * ERF_HALO_GAIN;
				float normRight = (sp.proj[0].right - 0.5f) * 2 * ERF_HALO_GAIN;
				assert(normRight >= normLeft);
				part = 0.5f * (erf(normRight) - erf(normLeft));
				assert(part >= 0.0f);
				assert(part <= 1.0f);
				float totalPartPart = part;
				if (i == 0 || i == integrPoints - 1)
					totalPartPart *= 0.5f;
				res.totalPart += totalPartPart;
			}
			if (i == 0)
				res.startPart = part;
			else if (i == integrPoints - 1)
				res.endPart = part;
			relBearing += drx;
		}
		res.totalPart /= (integrPoints - 1);
		assert(!isNaN(res.totalPart));
		return res;
	}

	ushort[] getBroadbandData(int antennaIdx) const
	{
		ushort[] res;
		m_ant[antennaIdx].imprint(res);
		return res;
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
			// rotation relative to hydrophone transform
			const float rot;
			// true if listenDir belongs to this antenna
			bool listenCell;
			// relative bearing of left edge of first beam from the left
			const float beam0Left;
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
			assert(!isNaN(m_baseSeaNoise.val));
			assert(!isNaN(m_baseFlowNoiseStart.val));
			assert(!isNaN(m_baseFlowNoiseEnd.val));
			float isoIntens = m_baseSeaNoise +
				0.5f * (m_baseFlowNoiseStart + m_baseFlowNoiseEnd);
			// we actually draw average bin intensity
			isoIntens /= m_listenToCellR * GLOBAL_SRATE / 2;
			foreach (ref c; beams)
				c += isoIntens;
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

		int sectorNormToCell(float norm)
		{
			return max(0, min(beams.length - 1, floor(norm * beams.length).lrint)).to!int;
		}

		/// returns true if source is visible for this antennae
		bool precalcForAntennae(int antIdx, ref SourcePrecalc p)
		{
			float bearingErr = uniform(-m_bearingErrNoise, m_bearingErrNoise);

			AntennaePrecalc* antPrec = &p.antPrec[antIdx];

			antPrec.relBearing1 = clampAnglePi(
				p.worldBearingStart + bearingErr - m_prevRot - rot);
			antPrec.relBearing2 = clampAnglePi(
				p.worldBearingEnd + bearingErr - m_transform.wrotation - rot);

			Sector allCellsSect = Sector(beam0Left, -beam0Left);
			SectorIntersection sectIsec1 = projectSectorsIntersect(
				Sector(
					antPrec.relBearing1 + p.haloBound,
					antPrec.relBearing1 - p.haloBound),
				allCellsSect);
			assert(sectIsec1.count < 2);
			SectorIntersection sectIsec2 = projectSectorsIntersect(
				Sector(
					antPrec.relBearing2 + p.haloBound,
					antPrec.relBearing2 - p.haloBound),
				allCellsSect);
			assert(sectIsec2.count < 2);

			// let's check visibility of this source
			antPrec.beamStart = beams.length.to!int;
			antPrec.beamEnd = -1;
			if (sectIsec1.count == 0 && sectIsec2.count == 0)
				return false;

			// FIXME: we don't handle the case when the target passes begind the tail

			// now we operate on raw non-intersected projections
			SectorProjection proj1 = projectSectors(
				Sector(
					antPrec.relBearing1 + p.haloBound,
					antPrec.relBearing1 - p.haloBound),
				allCellsSect);
			SectorProjection proj2 = projectSectors(
				Sector(
					antPrec.relBearing2 + p.haloBound,
					antPrec.relBearing2 - p.haloBound),
				allCellsSect);
			antPrec.beamStart = min(antPrec.beamStart,
				sectorNormToCell(proj1.left));
			antPrec.beamEnd = max(antPrec.beamEnd,
				sectorNormToCell(proj1.right));
			antPrec.beamStart = min(antPrec.beamStart,
				sectorNormToCell(proj2.left));
			antPrec.beamEnd = max(antPrec.beamEnd,
				sectorNormToCell(proj2.right));
			return antPrec.beamEnd >= antPrec.beamStart;
		}

		void applyBuiltIntensity(int antIdx, ref SourcePrecalc p)
		{
			assert(p.components > 0);
			AntennaePrecalc antPrec = p.antPrec[antIdx];
			float bandSum = 0.0f;
			//trace("p.bandSum = ", p.bandSum);
			for (int i = 0; i < p.components; i++)
				bandSum += p.bandSum[i].val;
			assert(!isNaN(bandSum));
			// we actually draw average bin intensity
			bandSum /= GLOBAL_SRATE / 2;
			float omniMult = p.omniFactorEnd * m_directivity * m_omniNoiseMult;
			if (omniMult > 0.0f)
			{
				foreach (ref beam; beams)
					beam += bandSum * omniMult;
			}
			// apply broadband power to beams
			for (int beamId = antPrec.beamStart; beamId <= antPrec.beamEnd; beamId++)
			{
				float beamLeft = beam0Left - beamId * m_beamAngle;
				float beamRight = beamLeft - m_beamAngle;
				float powerPart = integrateBetweenBeams(beamLeft, beamRight,
					antPrec.relBearing1, antPrec.relBearing2, p.haloBound).totalPart;
				assert(!isNaN(powerPart));
				if (powerPart > omniMult)
					beams[beamId] += bandSum * (1.0f - omniMult) * powerPart;
			}
		}
	}
}


unittest
{

	import imageformats;

	// print passive sonar data to PNG image
	static void printToPng(string filename, IntensityLevel[][] data, dB zeroLevel, dB maxLvl)
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
				assert(!isNaN(raw));
				minRaw = fmin(minRaw, raw);
				maxRaw = fmax(maxRaw, raw);
				dB transformed = (raw - zeroLevel) / dynRange;
				transformed = fmax(0.0f, fmin(1.0f, transformed));
				pixels[idx++] = (transformed * ubyte.max).to!ubyte;
			}
		write_png(filename, width, height, pixels, 1);
		trace(filename, " written, min/max raw dB: ", minRaw, " ", maxRaw);
	}


	import std.array;
	import std.algorithm: map, maxElement;
	import std.range;
	import std.stdio;
	import core.time: MonoTime;
	import dsubs_sound.image;
	import dsubs_sound.wav;

	DsubsSoundOpenclCtx ctx = s_clCtx;
	CommandQueue q = ctx.queue(0);
	Transform2D propTrans = new Transform2D();
	PropellerSound prop = new PropellerSound(propTrans, stdPropellerProto());
	float freqPerMs = 2.19f / 17.0f;
	float[] speeds = [1.0f, 3.0f, 5.0f, 7.5f, 10.0f, 12.5f, 15.0f, 17.0f];
	float[] relBearings = iota(0, speeds.length).map!(
		i => (dgr2rad(75) - i * dgr2rad(150) / (speeds.length - 1)).to!float).array;
	trace("relative bearings: ", relBearings);

	HydrophonePrototype hp = HydrophonePrototype(
		[0.0f],
		250, GLOBAL_SRATE / 2, dgr2rad(210.0f), 210, 2.0 / 90.0f, 3.0f);
	Hydrophone h = new Hydrophone(q, new Transform2D(), hp);
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
		h.resetAndStartIsotropic(q);
		foreach (j, float spd; speeds)
		{
			float freq = spd * freqPerMs;
			propTrans.position = rotateVector(vec2d(0.0, (i + 1) * -150.0), relBearings[j]);
			prop.preUpdate(freq, spd);
			prop.postUpdate(freq, spd, 1.0f);
			h.applySoundSource(q, prop);
		}
		h.flushSourceQueue();
		h.endIsotropic();
		h.m_ant[0].imprint(ilevels[i]);
	}
	printToPng("std_hydrophone_vs_std_propeller_30km.png", ilevels, 0.0f, 90.0f);

	// test own speed vs detection capability
	float dspd = mps2kts(17) / ilevels.length;
	for (size_t i = 0; i < ilevels.length; i++)
	{
		h.onPreSimulation();
		h.ktsStart = h.ktsEnd = spdKts + dspd * i;
		h.transform.rotation = PI + i / 10.0f;
		h.resetAndStartIsotropic(q);
		foreach (j, float spd; speeds)
		{
			float freq = spd * freqPerMs;
			propTrans.position = rotateVector(vec2d(0.0, -2000.0), relBearings[j]);
			prop.preUpdate(freq, spd);
			prop.postUpdate(freq, spd, 1.0f);
			h.applySoundSource(q, prop);
		}
		h.flushSourceQueue();
		h.endIsotropic();
		h.m_ant[0].imprint(ilevels[i]);
	}
	printToPng("std_hydrophone_0-17ms_2km_target.png", ilevels, 0.0f, 90.0f);

	// generate sound sample of cavitating std_propeller on 1km range
	propTrans.position = vec2d(0.0, -1000.0).rotateVector(dgr2rad(3));
	h.listenDir = PI;
	float spd = 15.0f;
	float freq = spd * freqPerMs;
	trace("fundamental shaft frequency = ", freq);
	h.ktsStart = h.ktsEnd = mps2kts(0);
	h.transform.rotation = PI;
	h.onPreSimulation();

	float[] samples;
	samples.length = GLOBAL_SRATE * 8;
	for (int i = 0; i < 8; i++)
	{
		prop.preUpdate(freq, spd);
		propTrans.position = vec2d(0.0, -1000.0).rotateVector(
			dgr2rad(3) - (i + 1) * dgr2rad(6.0f / 8));
		prop.postUpdate(freq, spd, 1.0f);
		h.resetAndStartIsotropic(q);
		assert(h.m_listenDirValid);
		assert(h.m_ant[0].listenCell >= 0);
		h.applySoundSource(q, prop);
		h.flushSourceQueue();
		h.endIsotropic();
		h.finalizeListenTds(q);
		q.s_tds.enqueueRead(q,
			samples[i * GLOBAL_SRATE .. (i + 1) * GLOBAL_SRATE]).release();
	}
	q.finish();
	// trace("samples: ", samples[0..16]);
	float maxp = samples.map!(a => a.abs).maxElement;
	assert(!isNaN(maxp));
	trace("std_hydrophone_vs_std_propeller_cav_1km maxp: ", maxp);
	writeWavFile("std_hydrophone_vs_std_propeller_cav_1km.wav",
		samples, 0.8f / maxp, GLOBAL_SRATE);

	// generate sound sample of silent-running std_propeller on 1km range
	propTrans.position = vec2d(0.0, -1000.0).rotateVector(dgr2rad(3));
	h.listenDir = PI;
	spd = 4.0f;
	freq = spd * freqPerMs;
	trace("fundamental shaft frequency = ", freq);
	h.ktsStart = h.ktsEnd = mps2kts(0);

	samples.length = GLOBAL_SRATE * 8;
	for (int i = 0; i < 8; i++)
	{
		prop.preUpdate(freq, spd);
		propTrans.position = vec2d(0.0, -1000.0).rotateVector(
			dgr2rad(3) - (i + 1) * dgr2rad(6.0f / 8));
		prop.postUpdate(freq, spd, 1.0f);
		h.resetAndStartIsotropic(q);
		assert(h.m_listenDirValid);
		assert(h.m_ant[0].listenCell >= 0);
		h.applySoundSource(q, prop);
		h.flushSourceQueue();
		h.endIsotropic();
		h.finalizeListenTds(q);
		q.s_tds.enqueueRead(q,
			samples[i * GLOBAL_SRATE .. (i + 1) * GLOBAL_SRATE]).release();
	}
	q.finish();
	// trace("samples: ", samples[0..16]);
	maxp = samples.map!(a => a.abs).maxElement;
	assert(!isNaN(maxp));
	trace("std_hydrophone_vs_std_propeller_1km maxp: ", maxp);
	writeWavFile("std_hydrophone_vs_std_propeller_1km.wav",
		samples, 0.8f / maxp, GLOBAL_SRATE);
}