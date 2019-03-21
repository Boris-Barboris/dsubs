module dsubs_client.game.cic.tracking;

import std.array: array, appender;
import std.algorithm;
import std.range;

import dsubs_common.math.angles;
import dsubs_common.api.entities;

import dsubs_client.game.cic.protocol;
import dsubs_client.game.cic.messages;
import dsubs_client.game.cic.entities;
import dsubs_client.common;


private struct WaterfallSlice
{
	AntennaeData[] data;
	usecs_t atTime;
	double worldRot;
	vec2d worldPos;
}

private struct HydrophoneTrackerContext
{
	HydrophoneTracker tracker;
	short counter = TRACKER_GEN_FREQ - 1;			/// increases with each acoustics update
	short lossCounter = TRACKER_LOSS_MARGIN - 2;	/// this many times the tracker did not found a signal it was bound to
	double prevWrot;		/// last time the tracker was active this was it's rotation
	usecs_t prevTime;		/// same for time
	double angVel = 0.0;	/// angular velocity of a tracker.
}

private struct Peak
{
	float rot;		/// world-space rotation
	float dist = float.max;
	bool locked;	/// tracker occupies this peak
}

private
{
	/// ray data will be generated after each TRACKER_GEN_FREQ data were received
	enum short TRACKER_GEN_FREQ = 6;
	/// tracker is automatically switched to inactive state after this many update cycles with
	/// no signal found.
	enum short TRACKER_LOSS_MARGIN = 5;
	enum float EXTRAPOLATION_MARGIN = dgr2rad(10);
}

final class WaterfallAnalyzer
{
	private
	{
		WaterfallSlice m_lastSlice;
		int m_sensorIdx;
		const HydrophoneTemplate m_tmpl;
		HydrophoneTrackerContext*[TrackerId] m_trackers;
		Peak[] m_peaks, m_freePeaks;
		int m_min;

		enum DETECT_MARGIN = ushort.max / 20;
	}

	this(const HydrophoneTemplate tmpl, int sensorIdx)
	{
		m_tmpl = tmpl;
		m_sensorIdx = sensorIdx;
		m_peaks.reserve(32);
	}

	/// Record new hydrophone data and analyze it. Move or deactivate trackers.
	void processNewData(AntennaeData[] data, KinematicSnapshot subSnap)
	{
		m_lastSlice.data = data;
		m_lastSlice.atTime = subSnap.atTime;
		m_lastSlice.worldRot = subSnap.rotation + m_tmpl.mount.rotation;
		m_lastSlice.worldPos = subSnap.position + rotateVector(m_tmpl.mount.mountCenter, subSnap.rotation);

		// recalculate min
		m_min = int.max;
		foreach (AntennaeData d; data)
			m_min = min(m_min, minElement(d.beams));

		// find all peaks and write them to array
		m_peaks.length = 0;
		m_freePeaks.length = 0;
		int beamCount = data[0].beams.length.to!int;
		foreach (i, AntennaeData d; data)
		{
			double andLeftWrot = m_lastSlice.worldRot + m_tmpl.antRots[i] + m_tmpl.fov / 2;
			ushort[] beams = m_lastSlice.data[i].beams;
			foreach (j, ushort ilevel; beams)
			{
				ushort ilevelPrev = j > 0 ? beams[j - 1] : ushort.max;
				ushort ilevelNext = j < beams.length - 2 ? beams[j + 1] : ushort.max;
				if (ilevel > (m_min + DETECT_MARGIN) &&
					ilevel >= ilevelPrev && ilevel > ilevelNext)
				{
					// we've found the peak
					double beamRot = clampAngle(andLeftWrot -
						(j + 0.5f) * (m_tmpl.fov / beamCount));
					m_peaks ~= Peak(beamRot);
				}
			}
		}
		trace("current peaks: ", m_peaks);

		// Update active trackers
		HydrophoneTrackerContext*[] trackers = m_trackers.byValue.
			filter!(t => t.tracker.state == TrackerState.active).array;
		// trackers without lost signals must bind to peaks first
		trackers.sort!"a.lossCounter < b.lossCounter";
		m_freePeaks = m_peaks;
		foreach (HydrophoneTrackerContext* htc; trackers)
		{
			float sinceLast = (subSnap.atTime - htc.prevTime) / 1e6f;
			float expextedWrot = htc.prevWrot + htc.angVel * sinceLast;
			assert(!isNaN(expextedWrot));
			if (m_freePeaks.length > 0)
			{
				// try to find the closest to expextedWrot peak
				foreach (ref Peak p; m_freePeaks)
					p.dist = angleDist(p.rot, expextedWrot).fabs;
				m_freePeaks.sort!"a.dist < b.dist";
				if (m_freePeaks[0].dist <= EXTRAPOLATION_MARGIN * min(sinceLast, TRACKER_LOSS_MARGIN))
				{
					m_freePeaks[0].locked = true;
					htc.lossCounter = 0;
					htc.angVel = m_freePeaks[0].dist / sinceLast;
					htc.prevTime = subSnap.atTime;
					htc.tracker.bearing = htc.prevWrot = m_freePeaks[0].rot;
					htc.counter = (htc.counter + 1) % TRACKER_GEN_FREQ;
					m_freePeaks = m_freePeaks[1 .. $];
				}
				else
					htc.lossCounter = min(htc.lossCounter + 1, TRACKER_LOSS_MARGIN).to!short;
			}
			else
			{
				htc.lossCounter = min(htc.lossCounter + 1, TRACKER_LOSS_MARGIN).to!short;
			}
			// too many cycles without a trace, deactivate tracker
			if (htc.lossCounter == TRACKER_LOSS_MARGIN)
				htc.tracker.state = TrackerState.inactive;
		}
	}

	/// allocate array of rotations and copy peaks into it
	float[] getPeaks()
	{
		float[] res;
		res.length = m_peaks.length;
		for (int i = 0; i < m_peaks.length; i++)
			res[i] = m_peaks[i].rot;
		return res;
	}

	/// allocate array of rotations and copy all trackers into it
	HydrophoneTracker[] getTrackers()
	{
		HydrophoneTracker[] res;
		res.reserve(m_trackers.length);
		foreach (tc; m_trackers.byValue)
			res ~= tc.tracker;
		return res;
	}

	void mergeTrackers(ContactId source, ContactId dest)
	{
		TrackerId sourceId = TrackerId(m_sensorIdx, source);
		TrackerId destId = TrackerId(m_sensorIdx, dest);
		HydrophoneTrackerContext** sourceCtx = sourceId in m_trackers;
		if (sourceCtx is null)
			return;
		HydrophoneTrackerContext** destCtx = destId in m_trackers;
		if (destCtx is null || (*sourceCtx).tracker.state == TrackerState.active)
		{
			(*sourceCtx).tracker.id.ctcId = dest;
			m_trackers[destId] = *sourceCtx;
		}
		m_trackers.remove(sourceId);
	}

	bool dropTracker(ContactId cid)
	{
		TrackerId tid = TrackerId(m_sensorIdx, cid);
		return m_trackers.remove(tid);
	}

	HydrophoneTracker createTracker(TrackerId tid, float bearing)
	{
		assert(tid.sensorIdx == m_sensorIdx);
		HydrophoneTrackerContext* ctx = new HydrophoneTrackerContext(
			HydrophoneTracker(tid, bearing, TrackerState.active));
		ctx.prevWrot = bearing;
		ctx.prevTime = m_lastSlice.atTime;
		m_trackers[tid] = ctx;
		return ctx.tracker;
	}

	/// Force-update tracker bearing, reset it's state to active and give it 2 cycles
	/// to lock on the target. Returns true if the update was made.
	bool updateTracker(ContactId cid, float bearing, out HydrophoneTracker newState)
	{
		TrackerId tid = TrackerId(m_sensorIdx, cid);
		HydrophoneTrackerContext** ctxPtr = tid in m_trackers;
		if (ctxPtr is null)
			return false;
		HydrophoneTrackerContext* ctx = *ctxPtr;
		ctx.angVel = 0.0;
		ctx.prevTime = m_lastSlice.atTime;
		ctx.lossCounter = TRACKER_LOSS_MARGIN - 2;
		ctx.tracker.state = TrackerState.active;
		ctx.tracker.bearing = bearing;
		newState = ctx.tracker;
		return true;
	}

	/// Generate contact data from active trackers wich counters are in the right position
	ContactData[] generateRayData()
	{
		ContactData[] res;
		foreach (tc; m_trackers.byValue)
		{
			if (tc.tracker.state == TrackerState.active && tc.counter == 0 && tc.lossCounter == 0)
			{
				ContactData data = ContactData(-1, tc.tracker.id.ctcId, m_lastSlice.atTime,
					DataSource(DataSourceType.Hydrophone, m_sensorIdx), DataType.Ray);
				RayData ray = RayData(m_lastSlice.worldPos, tc.tracker.bearing);
				data.data.ray = ray;
				res ~= data;
			}
		}
		return res;
	}
}