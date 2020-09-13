module dsubs_sound.hydrophone;

import std.algorithm.comparison: min, max;
import std.algorithm.iteration: sum;
import std.algorithm: canFind, map;
import std.array: array;
import std.range;
import std.mathspecial;

import imageformats;

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
	/// lower is better
	float directivity;
	dB baseNoise = 3.0f;
	float bearingErrNoise = 4e-3f;
	float flowNoiseMult = 1e-5f;
	float omniNoiseMult = 0.025f;
	/// client listens to beam of this size
	float listenSpan = dgr2rad(3);
	/// water dissipation modifier
	float dissMod = 4.0f;
	/// coaxial towed array can only focus on the cone, so it's contacts are mirrored.
	bool mirrored = false;
	float localNoiseRangeCutoff = 200.0f;
	dB imageBlackLevel = 5.0f;
	dB imageWhiteLevel = 90.0f;
	float pcbMaxPressure = 50.0f;
	string filterName;
}


interface IFlowNoiseMultiplier
{
	float getFlowNoiseMult();
}


/// Result of sound source projection on a hydrophone
struct SourceImprint
{
	SoundSource source;
	IntensityLevel backgroundLevel;
	/// If this is an omni source for the hydrophone, this is omni component intensity.
	Intensity ownOmniIntensity;
	IntensityLevel signalLevel;
	// omni sources have this true if they are heard only by their
	// omni component.
	bool directionAvailable;
}


/// Hydrophone is a collection of identical antennaes.
final class Hydrophone
{
	this(CommandQueue q, Transform2D t, ref const HydrophonePrototype p)
	{
		assert(p.minFreq >= 20 && p.maxFreq >= p.minFreq && p.maxFreq <= GLOBAL_SRATE);
		m_transform = t;
		m_minFreq = p.minFreq;
		m_tdsFilter = p.filterName.length ? q.ctx.getFilter(p.filterName) :
			q.ctx.getFilter("octaveHp" ~ m_minFreq.to!string);
		m_maxFreq = p.maxFreq;
		assert(m_maxFreq <= GLOBAL_SRATE / 2);
		m_directivity = p.directivity;
		m_baseNoise = p.baseNoise;
		m_dissMod = p.dissMod;
		m_localNoiseRangeCutoff = p.localNoiseRangeCutoff;
		m_span = p.antennaeSpan;
		m_listenSpan = p.listenSpan;
		m_mirrored = p.mirrored;
		m_imageBlackLevel = p.imageBlackLevel;
		m_imageWhiteLevel = p.imageWhiteLevel;
		m_pcbMaxPressure = p.pcbMaxPressure;
		if (m_mirrored)
			assert(p.antennaeRots.length == 1,
				"mirrored hydrophone cannot have more than 1 antennae");
		m_bearingErrNoise = p.bearingErrNoise;
		m_flowNoiseMult = p.flowNoiseMult;
		m_omniNoiseMult = p.omniNoiseMult;
		assert(m_span > 0.0f && m_span <= 2f * cast(float)PI, m_span.to!string);
		assert(p.beamCount > 0);
		m_beamCount = p.beamCount;
		m_beamAngle = m_span / p.beamCount;
		m_listenToCellR = m_listenSpan / m_beamAngle;
		foreach (rot; p.antennaeRots)
			m_ant ~= new Antennae(p.beamCount, rot);
		onPreKinematics += &savePrevPos;
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

	/// torpedo tubes want to modify flow noise by being open or closed
	IFlowNoiseMultiplier[] flowNoiseMultipliers;

	/// invoked by simulator before kinematic update happens
	Event!(void delegate()) onPreKinematics;
	/// invoked by simulator right after kinematic update happens
	Event!(void delegate()) onPostKinematics;

	private
	{
		Transform2D m_transform;
		vec2d m_prevPos;
		double m_prevRot = 0.0;
		Antennae[] m_ant;
		FIRFilter* m_tdsFilter;
		int m_minFreq, m_maxFreq;
		int m_beamCount;
		float m_span;
		float m_beamAngle;
		float m_listenSpan;
		float m_listenToCellR;
		float m_directivity;
		float m_bearingErrNoise;
		float m_flowNoiseMult;
		float m_omniNoiseMult;
		float m_localNoiseRangeCutoff;
		float m_dissMod;
		dB m_baseNoise;
		dB m_imageBlackLevel;
		dB m_imageWhiteLevel;
		float m_pcbMaxPressure;
		bool m_mirrored;

		/// speed in knots at the start of integration
		float m_ktsStart = 0.0f;
		float m_ktsEnd = 0.0f;

		enum float MAX_HALO = dgr2rad(20);
		enum float HALO_GAIN = 1.75f;
		enum float SOUND_HALO_GAIN = 1.5f;
		enum float ERF_HALO_GAIN = 2.0f;
		enum float ISOTROPIC_VAR = 2.0;
		enum float LOCAL_NOISE_RANGE_FULL = 10.0f;

		// broadband sea background noise intensity
		Intensity m_baseSeaNoise;
		Buffer m_baseSeaNoiseBuf;
		// broadband flow noise intensity
		Intensity m_baseFlowNoiseStart;
		Intensity m_baseFlowNoiseEnd;
		Intensity m_totalOmni;
		Buffer m_baseFlowNoiseStartBuf;
		Buffer m_baseFlowNoiseEndBuf;
		AsyncEvent m_isotropicReadyEvt;

		// when false, no calculations should be performed
		bool m_shouldBeActive = true;
		// additional toggle that is used by towed mechanism.
		bool m_canBeActive = true;
		// set to true to never generate Tds for m_listenDir.
		bool m_muteTds;
		// world-space direction the player is listening to
		float m_listenDir = 0.0f;
		// false when no active antenna has a beam for chosen listen Dir
		bool m_listenDirValid;
		bool m_needPrevReset;
		// bots need to programatically process records of foreign sources.
		// set this to true in order to
		bool m_maintainImprints;
		// Array of sources that were applied to this hydrophone antennaes.
		SourceImprint[] m_imprints;

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

	@property bool mirrored() const { return m_mirrored; }

	@property Transform2D transform() { return m_transform; }

	@property bool active() const { return m_shouldBeActive && m_canBeActive; }

	@property bool canBeActive() const { return m_canBeActive; }

	@property bool listenDirValid() const { return m_listenDirValid; }

	@property size_t antennaCount() const { return m_ant.length; }

	/// single antennae span, radians.
	@property float span() const { return m_span; }

	/// number of beams in antennae. Effectively the length of broadbandData array.
	@property int beamCount() const { return m_beamCount; }

	@property void shouldBeActive(bool rhs)
	{
		if (!m_shouldBeActive && rhs && m_canBeActive)
			m_needPrevReset = true;
		m_shouldBeActive = rhs;
		if (!rhs)
			m_listenDirValid = false;
	}

	@property void canBeActive(bool rhs)
	{
		if (!m_canBeActive && rhs && m_shouldBeActive)
			m_needPrevReset = true;
		m_canBeActive = rhs;
		if (!rhs)
			m_listenDirValid = false;
	}

	@property bool muteTds() const { return m_muteTds; }

	@property void muteTds(bool rhs) { m_muteTds = rhs; }

	@property bool maintainImprints() const { return m_maintainImprints; }

	@property void maintainImprints(bool rhs) { m_maintainImprints = rhs; }

	@property SourceImprint[] imprints() { return m_imprints; }

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
	/// to m_pcb array of shorts
	void startFinalizePcbData(CommandQueue q)
	{
		finalizeListenTds(q);
		// this kernel swallows NaNs in tds: returns pcbMaxPressure array.
		Kernel k = q.mk_toShortPcb;
		k.setArg(0, q.s_tds.mem);
		k.setArg(1, q.s_pcbBuf.mem);
		k.setArg(2, m_pcbMaxPressure);
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
			if (m_listenDirValid || m_muteTds)
			{
				ant.listenCell = false;
				continue;
			}
			bool belongs = belongsToAntennae(m_listenDir, ant);
			if (belongs)
			{
				m_listenDirValid = true;
				ant.listenCell = true;
			}
			else
				ant.listenCell = false;
		}
	}

	private bool belongsToAntennae(double worldBearing, Antennae ant)
	{
		double relBearing = clampAnglePi(
			worldBearing - m_transform.wrotation - ant.rot);
		return (relBearing <= m_span / 2) && (relBearing >= -m_span / 2);
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
		float flowNoiseMultExternal = 1.0f;
		foreach (fnm; flowNoiseMultipliers)
			flowNoiseMultExternal *= fnm.getFlowNoiseMult();
		assert(!isNaN(flowNoiseMultExternal));

		void dispatchFlowCalc(ref ISpectrum spec, float kts)
		{
			spec.patch(q, 0.0f);
			Kernel k = q.mk_generateFlowNoise;
			k.setArg(0, spec.mem);
			k.setArg(1, m_flowNoiseMult * m_directivity *
				m_listenToCellR * flowNoiseMultExternal);
			k.setArg(2, kts.abs);
			k.setArg(3, ISOTROPIC_VAR);
			k.setArg(4, uintSeed());
			k.enqueue(q, 1, [m_minFreq - 1],
				[m_maxFreq - m_minFreq + 1], null, null);
		}
		assert(!isNaN(m_ktsStart));
		dispatchFlowCalc(q.s_ispec, m_ktsStart);
		assert(!isNaN(m_ktsEnd));
		dispatchFlowCalc(q.s_ispec2, m_ktsEnd);

		// !!don't forget to scale it's value by m_listenToCellR!!
		q.s_ispec.reduceSum(q, m_baseFlowNoiseStartBuf, m_minFreq, m_maxFreq);
		m_baseFlowNoiseStartBuf.enqueueFullRead(q, &m_baseFlowNoiseStart, null).release();

		q.s_ispec2.reduceSum(q, m_baseFlowNoiseEndBuf, m_minFreq, m_maxFreq);
		m_baseFlowNoiseEndBuf.enqueueFullRead(q, &m_baseFlowNoiseEnd, null).release();

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
		m_imprints.length = 0;
		m_totalOmni = 0.0f;
		startCalculateSeaNoise(q);
		startCalculateFlowNoise(q);
		m_isotropicReadyEvt = q.insertMarker();
		foreach (a; m_ant)
			a.reset();
	}

	private void awaitIsotropicBuffers()
	{
		// if needed
		if (m_isotropicReadyEvt !is AsyncEvent.init)
		{
			m_isotropicReadyEvt.waitFor();
			m_isotropicReadyEvt = AsyncEvent.init;
		}
	}

	/// Call after resetAndStartIsotropic
	void endIsotropic()
	{
		awaitIsotropicBuffers();
		foreach (a; m_ant)
			a.applyIsotropic();
	}

	private struct AntennaePrecalc
	{
		SectorIntersection affectedBeamsProj;
		double relBearing1;
		double relBearing2;
		// true when source is visible for this antennae beams
		bool inside;
	}

	// precalculated sound source context
	private struct SourcePrecalc
	{
		SoundSource source;
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
		Tds*[MAX_COMPONENTS] tds;			/// persistent prepared tds buffers
		AsyncEvent evt;						/// marker that finishes when bandSum and tds
			/// are ready.
		int components = 0;
	}

	// Sound sources are enqueued and processed asynchronously by opencl.
	// In order to generate broadband beam data on cpu we await band sums,
	// calculated in opencl. That requires queuing in order to be efficient.
	private SourcePrecalc*[] m_sourceQueue;


	/// precalculate world-space values and key gains for sound source.
	private SourcePrecalc precalcForSource(SoundSource s)
	{
		SourcePrecalc res;
		res.source = s;
		res.dirStart = s.prevPos - m_prevPos;
		res.dirEnd = s.position - m_transform.wposition;
		res.rangeStart = max(10.0, res.dirStart.length);
		res.rangeEnd = max(10.0, res.dirEnd.length);
		res.omniFactorStart = max(s.minOmniFactor(res.rangeStart),
			caclOmniFactor(res.rangeStart, m_localNoiseRangeCutoff));
		res.omniFactorEnd = max(s.minOmniFactor(res.rangeEnd),
			caclOmniFactor(res.rangeEnd, m_localNoiseRangeCutoff));
		assert(res.range > 0.0);
		res.worldBearingStart = courseAngle(res.dirStart);
		// FIXME: we always assume the shortest rotation to maintain angle continuity.
		res.worldBearingEnd = res.worldBearingStart + angleDist(
			courseAngle(res.dirEnd), res.worldBearingStart);
		res.haloBaseRadius = (atan(s.radius / res.range) + pointHaloAngle(res.range)) *
			(1 + uniform(-0.06f, 0.06f));
		res.haloBound = fmin(HALO_GAIN * res.haloBaseRadius, MAX_HALO);
		return res;
	}

	private static float caclOmniFactor(float range, float cutoff)
	{
		if (range <= LOCAL_NOISE_RANGE_FULL)
			return 1.0f;
		float linGain = max(0.0f, 1.0f -
			(range - LOCAL_NOISE_RANGE_FULL) / cutoff);
		return pow(linGain, 2);
	}

	// thread-safe enqueuing of source calculation
	void applySoundSource(CommandQueue q, SoundSource s)
	{
		SourcePrecalc* prec = new SourcePrecalc();
		*prec = precalcForSource(s);
		bool isVisible = prec.omniFactorStart > 0.0f || prec.omniFactorEnd > 0.0f;
		foreach (i, a; m_ant)
		{
			isVisible |= a.precalcForAntennae(i.to!int, *prec);
		}
		if (!isVisible)
			return;
		// source is visible, let's issue sound rendering commands
		synchronized(this)
		{
			m_sourceQueue ~= prec;
		}
		startSourceCalc(q, s, prec);
	}

	/// Process source queue, enqueues tds summation and applies source intensities to
	/// beams. m_curTds is not ready at the end of this call.
	void flushSourceQueue(CommandQueue q)
	{
		foreach (SourcePrecalc* sp; m_sourceQueue)
			popSourceSignal(q, sp);
		m_sourceQueue.length = 0;
	}

	private void popSourceSignal(CommandQueue q, SourcePrecalc* prec)
	{
		int compCount = prec.components;
		if (compCount > 0)
		{
			if (prec.evt !is AsyncEvent.init)
				prec.evt.waitFor();
			for (int i = 0; i < compCount; i++)
			{
				// if there is a tds buffer, we need to add it to m_curTds
				if (prec.tds[i] !is null)
				{
					prec.tds[i].addTo(q, m_curTds);
					// explicit destroy of buffer, can be made immediately after enqueue
					// https://github.com/KhronosGroup/OpenCL-Docs/issues/45
					destroy(*prec.tds[i]);
				}
			}
			foreach (i, a; m_ant)
				a.applyBuiltIntensity(i.to!int, *prec);
			if (m_maintainImprints)
				appendToImprints(*prec);
		}
	}

	private void appendToImprints(ref SourcePrecalc sp)
	{
		SourceImprint imprint;
		imprint.source = sp.source;
		float signalIntensity = 0.0f;
		for (int i = 0; i < sp.components; i++)
		{
			if (isNormal(sp.bandSum[i].val))
				signalIntensity += sp.bandSum[i].val;
		}
		if (signalIntensity <= 0.0f)
			return;
		signalIntensity /= GLOBAL_SRATE / 2;
		bool visible = sp.antPrec[].map!(ap => ap.inside).canFind(true);
		float omniMult = sp.omniFactorEnd * m_directivity * m_omniNoiseMult;
		if (visible)
			imprint.directionAvailable = true;
		else
		{
			signalIntensity *= omniMult;
			imprint.directionAvailable = false;
		}
		// we wish to account for omni noise for AI-human parity
		if (omniMult > 0.0f)
		{
			imprint.ownOmniIntensity = Intensity(omniMult * signalIntensity);
			m_totalOmni += imprint.ownOmniIntensity;
		}
		// we replace noise floor by floor + 0.5 of variance
		imprint.backgroundLevel = IntensityLevel(
			0.5f * m_baseNoise + getIsotropicIntens().toDb);
		imprint.signalLevel = Intensity(signalIntensity).toDb();
		assert(!isNaN(imprint.signalLevel.val));
		// if signal level is statistically significant
		if (imprint.signalLevel > imprint.backgroundLevel)
			m_imprints ~= imprint;
	}

	void adjustImprintsToOmni()
	{
		if (m_totalOmni == 0.0f || !m_maintainImprints)
			return;
		foreach (ref SourceImprint si; m_imprints)
			si.backgroundLevel = Intensity(si.backgroundLevel.toLinear +
				m_totalOmni - si.ownOmniIntensity).toDb;
	}

	private void startSourceCalc(CommandQueue q, SoundSource s, SourcePrecalc* p)
	{
		assert(p !is null);
		bool needTds = m_listenDirValid;

		PowerIntegr integr;
		if (m_listenDirValid)
		{
			double left = m_listenDir + m_listenSpan / 2;
			double right = m_listenDir - m_listenSpan / 2;
			integr = integrateBetweenBeams(left, right,
				p.worldBearingStart, p.worldBearingEnd, p.haloBound * SOUND_HALO_GAIN);
			if (m_mirrored)
			{
				double leftMirrored = right + 2.0 * (m_prevRot - right);
				double rightMirrored = left + 2.0 * (m_prevRot - left);
				PowerIntegr integrMirror = integrateBetweenBeams(
					leftMirrored, rightMirrored,
					p.worldBearingStart, p.worldBearingEnd, p.haloBound * SOUND_HALO_GAIN);
				if (integrMirror.totalPart > integr.totalPart)
					integr = integrMirror;
			}
		}
		if (needTds && integr.totalPart == 0.0f && p.omniFactorStart == 0.0f &&
			p.omniFactorEnd == 0.0f)
		{
			needTds = false;
		}

		bool logMore = false; // this.m_beamCount > 50;
		bool needMarker;

		void onTdsReady(Intensity* bandIntSum, Buffer* bandIntensitySumBuf, Tds* tds)
		{
			assert(p.components < p.MAX_COMPONENTS);
			if (bandIntSum !is null)
			{
				assert(!isNaN(bandIntSum.val));
				// band intensity sum is already calculated on the CPU
				p.bandSum[p.components] = *bandIntSum;
			}
			else
			{
				// band intensity sum will arrive later from OpenCL
				assert(bandIntensitySumBuf !is null);
				AsyncEvent evt = bandIntensitySumBuf.enqueueFullRead(q,
					&p.bandSum[p.components], null);
				if (logMore)
				{
					// Stalls!
					evt.waitFor();
					trace(cast(void*) p.source,
						", source = ", p.source.owner.to!string,
						", comp = ", p.components,
						", bandsum = ", p.bandSum[p.components]);
				}
				else
				{
					evt.release();
					needMarker = true;
				}
			}
			if (needTds && tds)
			{
				float omniImultStart = p.omniFactorStart * m_directivity * m_omniNoiseMult;
				float omniImultEnd = p.omniFactorEnd * m_directivity * m_omniNoiseMult;
				dB intensStart = max(-60.0f, toDb(
					omniImultStart + (1.0f - omniImultStart) * integr.startPart));
				assert(intensStart <= 0.0f, intensStart.to!string);
				dB intensEnd = max(-60.0f, toDb(
					omniImultEnd + (1.0f - omniImultEnd) * integr.endPart));
				assert(intensEnd <= 0.0f, intensEnd.to!string);
				modulateILevelInterp(q, *tds, intensStart, intensEnd);
				p.tds[p.components] = tds;
				needMarker = true;
			}
			p.components++;
		}

		s.buildSignals(q, m_transform.wposition, m_prevPos, &onTdsReady,
			m_minFreq, m_maxFreq, needTds, m_dissMod, m_tdsFilter, logMore);

		// insert marker if there are things to await for
		if (needMarker)
			p.evt = q.insertMarker();
	}

	private struct PowerIntegr
	{
		float totalPart = 0.0f;
		float startPart;
		float endPart;
	}

	private static PowerIntegr integrateBetweenBeams(double left, double right,
		double brngStart, double brngEnd, float haloRadius, int integrPoints = 13)
	{
		assert(integrPoints >= 2);
		assert(right <= left);
		PowerIntegr res;
		double drx = (brngEnd - brngStart) / (integrPoints - 1);
		double relBearing = brngStart;
		assert(left >= right);
		Sector beamSector = Sector(left, right);
		for (int i = 0; i < integrPoints; i++)
		{
			SectorIntersection sp = projectSectorsIntersect(beamSector,
				Sector(relBearing + haloRadius, relBearing - haloRadius));
			assert(sp.count < 2);
			float part = 0.0f;
			if (sp.count == 1)
			{
				double normLeft = (sp.proj[0].left - 0.5f) * 2 * ERF_HALO_GAIN;
				double normRight = (sp.proj[0].right - 0.5f) * 2 * ERF_HALO_GAIN;
				assert(normRight >= normLeft, normLeft.to!string ~ " " ~
					normRight.to!string ~ " " ~ sp.proj[0].to!string ~ " beamSector: " ~
					beamSector.to!string ~ ", relBearing: " ~ relBearing.to!string ~
					", haloRadius: " ~ haloRadius.to!string);
				part = 0.5 * (erf(normRight) - erf(normLeft));
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

	private Intensity getIsotropicIntens()
	{
		assert(!isNaN(m_baseSeaNoise.val));
		assert(!isNaN(m_baseFlowNoiseStart.val));
		assert(!isNaN(m_baseFlowNoiseEnd.val));
		float isoIntens = m_baseSeaNoise +
			0.5f * (m_baseFlowNoiseStart + m_baseFlowNoiseEnd);
		// we actually draw average bin intensity.
		// m_listenToCellR scale is done here because we multiply by
		// in on GPU in order to get Tds signal of desired
		// magnitude for listen beam, which is of width different from cell.
		isoIntens /= m_listenToCellR * GLOBAL_SRATE / 2;
		return Intensity(isoIntens);
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
			float isoIntens = getIsotropicIntens();
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

		void imprint(ref ushort[] dest) const
		{
			dest.length = beams.length;
			foreach (i, const c; beams)
			{
				dB level = max(0.0f, IntensityLevel(
					c.toDb + uniform(0.0f, m_baseNoise) - m_imageBlackLevel));
				assert(!isNaN(level));
				dest[i] = lrint(
					min(float(ushort.max), level /
						(m_imageWhiteLevel - m_imageBlackLevel) * ushort.max)).to!ushort;
			}
		}

		/// map normalized antennae sector coordinate to index in the beams array.
		int sectorNormToBeam(float norm)
		{
			return max(0, min(beams.length - 1,
				floor(norm * beams.length).lrint)).to!int;
		}

		/// Returns true if source is visible for this antennae.
		bool precalcForAntennae(int antIdx, ref SourcePrecalc p)
		{
			float bearingErr = uniform(-m_bearingErrNoise, m_bearingErrNoise);

			AntennaePrecalc* antPrec = &p.antPrec[antIdx];

			// we do not clamp relative bearings, this causes rotation artifacts.
			antPrec.relBearing1 =
				p.worldBearingStart + bearingErr - m_prevRot - rot;
			antPrec.relBearing2 =
				p.worldBearingEnd + bearingErr - m_transform.wrotation - rot;

			// sector in antennae-local reference frame that spans all beams. It is
			// not moving.
			Sector allCellsSect = Sector(beam0Left, -beam0Left);
			// sector in antennae-local reference frame that spans all rays that the sound
			// is coming from to this antennae.
			assert(p.haloBound > 0);
			assert(p.haloBound <= 2 * PI);
			assert(antPrec.relBearing1 + p.haloBound > antPrec.relBearing1 - p.haloBound,
				antPrec.relBearing1.to!string ~ " " ~
				p.worldBearingStart.to!string ~ " " ~
				m_prevRot.to!string ~ " " ~
				bearingErr.to!string);
			Sector soundEmissionSect = Sector(
				max(antPrec.relBearing1 + p.haloBound, antPrec.relBearing2 + p.haloBound),
				min(antPrec.relBearing1 - p.haloBound, antPrec.relBearing2 - p.haloBound));
			assert(soundEmissionSect.left < soundEmissionSect.right + 2 * PI,
				(*antPrec).to!string ~ " p: " ~ p.to!string ~
				" prevRot " ~ m_prevRot.to!string ~
				" m_transform.wrotation " ~ m_transform.wrotation.to!string);
			antPrec.affectedBeamsProj = projectSectorsIntersect(
				soundEmissionSect, allCellsSect);
			antPrec.inside = antPrec.affectedBeamsProj.count > 0;
			if (antPrec.inside)
				assert(antPrec.affectedBeamsProj.proj[0].left !=
					antPrec.affectedBeamsProj.proj[0].right,
				(*antPrec).to!string);
			return antPrec.inside;
		}

		void applyBuiltIntensity(int antIdx, ref SourcePrecalc p)
		{
			assert(p.components > 0);
			AntennaePrecalc antPrec = p.antPrec[antIdx];
			float bandSum = 0.0f;
			//trace("p.bandSum = ", p.bandSum);
			for (int i = 0; i < p.components; i++)
			{
				float addedValue = p.bandSum[i].val;
				if (isNaN(addedValue))
				{
					error(p.source.to!string ~ " source with owner " ~
						p.source.owner.to!string ~
						" has returned NaN bandSum, it's precalc: " ~
						p.to!string);
				}
				else
					bandSum += addedValue;
			}
			// we actually draw average bin intensity
			bandSum /= GLOBAL_SRATE / 2;
			float omniMult = p.omniFactorEnd * m_directivity * m_omniNoiseMult;
			assert(omniMult <= 1.0f, p.to!string);
			assert(omniMult >= 0.0f, p.to!string);
			if (omniMult > 0.0f)
			{
				foreach (ref beam; beams)
					beam += bandSum * omniMult;
			}
			// apply directional broadband power to beams
			for (int i = 0; i < antPrec.affectedBeamsProj.count; i++)
			{
				SectorProjection proj = antPrec.affectedBeamsProj.proj[i];
				int beamStart = sectorNormToBeam(proj.left);
				int beamEnd = sectorNormToBeam(proj.right);
				for (int beamId = beamStart; beamId <= beamEnd; beamId++)
				{
					float beamLeft = beam0Left - beamId * m_beamAngle;
					float beamRight = beamLeft - m_beamAngle;
					float powerPart = integrateBetweenBeams(beamLeft, beamRight,
						antPrec.relBearing1, antPrec.relBearing2, p.haloBound).totalPart;
					assert(!isNaN(powerPart));
					if (powerPart > omniMult)
					{
						float addedIntensity = bandSum * (1.0f - omniMult) * powerPart;
						beams[beamId] += addedIntensity;
						if (m_mirrored)
							beams[$ - beamId - 1] += addedIntensity;
					}
				}
			}
		}
	}
}


/// print passive sonar data to PNG image
void printIlevelsToPng(string filename, IntensityLevel[][] data,
	dB zeroLevel = 0.0f, dB maxLvl = 90.0f)
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
}

void hydrophoneVsPropellerBalancingPlot(CommandQueue q,
	string testFileTitle, HydrophonePrototype hp,
	PropellerSoundPrototype pp, float shaftFreqPerMs, float minPropSpeed,
	float maxPropSpeed, float maxRange = 30000.0f, float maxListenerSpeed = 17.0f,
	int rowCount = 100, int spdMarksCount = 5)
{
	import std.array;
	import std.range;
	import std.algorithm;

	Transform2D propTrans = new Transform2D();
	PropellerSound prop = new PropellerSound(q, propTrans, pp);
	float[] propSpeeds = iota(minPropSpeed, maxPropSpeed + 0.1f,
		(maxPropSpeed - minPropSpeed) / 9).array;
	float[] relBearings = iota(0, propSpeeds.length).map!(
		i => (dgr2rad(75) - i * dgr2rad(150) / (propSpeeds.length - 1)).to!float).array;
	Hydrophone h = new Hydrophone(q, new Transform2D(), hp);
	IntensityLevel[][] ilevels;
	ilevels.length = rowCount * spdMarksCount;
	h.ktsStart = h.ktsEnd = 0.0f;

	float dspd = mps2kts(maxListenerSpeed) / (spdMarksCount - 1);
	float drange = maxRange / rowCount;

	for (size_t k = 0; k < spdMarksCount; k++)
	{
		h.transform.rotation = 0.0;
		for (size_t i = 0; i < rowCount; i++)
		{
			h.onPreKinematics();
			h.ktsStart = h.ktsEnd = dspd * k;
			// h.transform.rotation = -(i.to!double * 0.05);
			h.resetAndStartIsotropic(q);
			foreach (j, float spd; propSpeeds)
			{
				float shaftFreq = spd * shaftFreqPerMs;
				propTrans.position = rotateVector(vec2d(0.0, (i + 1) * drange),
					relBearings[j]);	// + i * 0.03
				prop.onPreKinematics();
				prop.preUpdate(shaftFreq, spd);
				prop.postUpdate(shaftFreq, spd, 1.0f);
				h.applySoundSource(q, prop);
			}
			h.flushSourceQueue(q);
			h.endIsotropic();
			h.m_ant[0].imprint(ilevels[i + k * rowCount]);
			h.onPostKinematics();
		}
	}
	printIlevelsToPng(testFileTitle ~ ".png", ilevels, 0.0f, 90.0f);
}


/*

unittest
{
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
	PropellerSound prop = new PropellerSound(q, propTrans, stdPropellerProto());
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
	h.onPreKinematics();
	float spdKts = mps2kts(0);
	h.ktsStart = h.ktsEnd = spdKts;

	hydrophoneVsPropellerBalancingPlot(q, "std_hydrophone_vs_stdProp_30km",
		hp, stdPropellerProto(), 2.19f / 17.0f, 1.0f, 17.0f);

	// for (size_t i = 0; i < ilevels.length; i++)
	// {
	// 	// h.onPreKinematics();
	// 	// h.transform.rotation = i * dgr2rad(0.5);
	// 	h.resetAndStartIsotropic(q);
	// 	foreach (j, float spd; speeds)
	// 	{
	// 		float freq = spd * freqPerMs;
	// 		propTrans.position = rotateVector(vec2d(0.0, (i + 1) * -150.0), relBearings[j]);
	// 		prop.onPreKinematics();
	// 		prop.preUpdate(freq, spd);
	// 		prop.postUpdate(freq, spd, 1.0f);
	// 		h.applySoundSource(q, prop);
	// 	}
	// 	h.flushSourceQueue();
	// 	h.endIsotropic();
	// 	h.m_ant[0].imprint(ilevels[i]);
	// }
	// printIlevelsToPng("std_hydrophone_vs_std_propeller_30km.png", ilevels, 0.0f, 90.0f);

	// // test own speed vs detection capability
	// float dspd = mps2kts(17) / ilevels.length;
	// for (size_t i = 0; i < ilevels.length; i++)
	// {
	// 	h.onPreKinematics();
	// 	h.ktsStart = h.ktsEnd = spdKts + dspd * i;
	// 	h.transform.rotation = PI + i / 10.0f;
	// 	h.resetAndStartIsotropic(q);
	// 	foreach (j, float spd; speeds)
	// 	{
	// 		float freq = spd * freqPerMs;
	// 		propTrans.position = rotateVector(vec2d(0.0, -2000.0), relBearings[j]);
	// 		prop.onPreKinematics();
	// 		prop.preUpdate(freq, spd);
	// 		prop.postUpdate(freq, spd, 1.0f);
	// 		h.applySoundSource(q, prop);
	// 	}
	// 	h.flushSourceQueue();
	// 	h.endIsotropic();
	// 	h.m_ant[0].imprint(ilevels[i]);
	// }
	// printIlevelsToPng("std_hydrophone_0-17ms_2km_target.png", ilevels, 0.0f, 90.0f);

	// generate sound sample of cavitating std_propeller on 1km range
	propTrans.position = vec2d(0.0, -1000.0).rotateVector(dgr2rad(3));
	h.shouldBeActive = false;
	h.shouldBeActive = true;
	h.listenDir = PI;
	float spd = 15.0f;
	float freq = spd * freqPerMs;
	trace("fundamental shaft frequency = ", freq);
	h.ktsStart = h.ktsEnd = mps2kts(0);
	h.transform.rotation = PI;
	h.onPreKinematics();

	float[] samples;
	samples.length = GLOBAL_SRATE * 8;
	for (int i = 0; i < 8; i++)
	{
		prop.onPreKinematics();
		prop.preUpdate(freq, spd);
		propTrans.position = vec2d(0.0, -1000.0).rotateVector(
			dgr2rad(3) - (i + 1) * dgr2rad(6.0f / 8));
		prop.postUpdate(freq, spd, 1.0f);
		h.maintainImprints = true;
		h.resetAndStartIsotropic(q);
		assert(h.m_listenDirValid);
		assert(h.m_ant[0].listenCell >= 0);
		h.applySoundSource(q, prop);
		h.flushSourceQueue();
		assert(h.imprints.length == 1);
		assert(h.imprints[0].source is prop);
		assert(h.imprints[0].directionAvailable);
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
	h.shouldBeActive = false;
	h.shouldBeActive = true;
	spd = 4.0f;
	freq = spd * freqPerMs;
	trace("fundamental shaft frequency = ", freq);
	h.ktsStart = h.ktsEnd = mps2kts(0);

	samples.length = GLOBAL_SRATE * 8;
	for (int i = 0; i < 8; i++)
	{
		prop.onPreKinematics();
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

	// test prerecorded source
	PrerecordedSoundPrototype psProto = PrerecordedSoundPrototype(
		s_clCtx.getWavFile("../dsubs_sound/big_iron_8192.wav"),
		15.0f, 90.0f);
	PrerecordedSoundSource psSource = new PrerecordedSoundSource(
		new Transform2D(), psProto, null);
	psSource.transform.position = vec2d(0.0, -10000.0);
	samples.length = GLOBAL_SRATE * 12;
	for (int i = 0; i < 12; i++)
	{
		psSource.onPreKinematics();
		h.resetAndStartIsotropic(q);
		assert(h.m_listenDirValid);
		assert(h.m_ant[0].listenCell >= 0);
		psSource.transform.position = vec2d(0.0, -10000.0 + 9500 / 11 * i);
		if (!psSource.finished)
			h.applySoundSource(q, psSource);
		h.flushSourceQueue();
		h.endIsotropic();
		h.finalizeListenTds(q);
		q.s_tds.enqueueRead(q,
			samples[i * GLOBAL_SRATE .. (i + 1) * GLOBAL_SRATE]).release();
		if (!psSource.finished)
			psSource.onPostAcoustics();
	}
	q.finish();
	maxp = samples.map!(a => a.abs).maxElement;
	assert(!isNaN(maxp));
	trace("std_hydrophone_vs_big_iron_1km maxp: ", maxp);
	writeWavFile("std_hydrophone_vs_big_iron_1km.wav",
		samples, 0.8f / maxp, GLOBAL_SRATE);
}

*/

unittest
{
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
	PropellerSoundPrototype pp = PropellerSoundPrototype(
			loadSpectrumFromImageAndWarp(q,
				"../dsubs_sound/minoga.png", 1.0f, 60, 110),
			loadSpectrumFromImageAndWarp(q,
				"../dsubs_sound/minoga_cav.png", 1.0f, 45, 130),
			cast(immutable) new TrochoidModulatorParams([
				Harmonic(1.0f, 0.25f),
				Harmonic(3.0f, 0.75f)],
				0.4, 0.7, -0.4),
			0.25f, dgr2rad(30), 5.0f, 0.03f, 0.7f
		);
	PropellerSound prop = new PropellerSound(q, propTrans, pp);
	HydrophonePrototype hp = HydrophonePrototype(
		[0.0f],
		250, GLOBAL_SRATE / 2, dgr2rad(210.0f), 210, 2.0 / 90.0f, 3.0f);
	Hydrophone h = new Hydrophone(q, new Transform2D(), hp);
	h.transform.rotation = PI; // good corner case
	propTrans.position = vec2d(0.0, -1000.0);
	float shaftRotFreq = 21.45f;
	float spd = 29.0f;

	// hydrophoneVsPropellerBalancingPlot(q, "std_hydrophone_vs_minoga_30km",
	// 	hp, pp, shaftRotFreq / spd, 20.0f, 29.0f);

	float[] samples;
	h.listenDir = PI;
	h.ktsStart = h.ktsEnd = 0.0f;
	h.shouldBeActive = true;
	samples.length = GLOBAL_SRATE * 4;
	for (int i = 0; i < 4; i++)
	{
		prop.onPreKinematics();
		prop.preUpdate(shaftRotFreq, spd);
		prop.postUpdate(shaftRotFreq, spd, 1.0f);
		h.resetAndStartIsotropic(q);
		h.applySoundSource(q, prop);
		h.flushSourceQueue(q);
		h.endIsotropic();
		h.finalizeListenTds(q);
		if (i < 4)
		{
			q.s_tds.enqueueRead(q,
				samples[i * GLOBAL_SRATE .. (i + 1) * GLOBAL_SRATE]).release();
		}
	}
	q.finish();
	float maxp = samples.map!(a => a.abs).maxElement;
	assert(!isNaN(maxp));
	writeWavFile("std_hydrophone_vs_current.wav",
		samples, 0.8f / maxp, GLOBAL_SRATE);
}
