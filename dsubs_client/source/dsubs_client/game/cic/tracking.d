module dsubs_client.game.cic.tracking;

import std.array: array, appender;
import std.algorithm;
import std.range;

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
}

private struct HydrophoneTrackerContext
{
	HydrophoneTracker tracker;
}


final class WaterfallAnalyzer
{
	private
	{
		WaterfallSlice m_lastSlice;
		const HydrophoneTemplate m_tmpl;
		HydrophoneTrackerContext*[TrackerId] m_trackers;
		double[] m_peaks;
		int m_min;

		enum DETECT_MARGIN = ushort.max / 20;
	}

	this(const HydrophoneTemplate tmpl)
	{
		m_tmpl = tmpl;
	}

	/// Record new hydrophone data and analyze it. Move or deactivate trackers.
	void processNewData(AntennaeData[] data, KinematicSnapshot subSnap)
	{
		m_lastSlice.data = data;
		m_lastSlice.atTime = subSnap.atTime;
		m_lastSlice.worldRot = subSnap.rotation + m_tmpl.mount.rotation;
		// recalculate min
		m_min = int.max;
		foreach (AntennaeData d; data)
			m_min = min(m_min, minElement(d.beams));
		// find all peaks and write them to array
		m_peaks.length = 0;
		int beamCount = data[0].beams.length.to!int;
		foreach (int i, AntennaeData d; data)
		{
			double andLeftWrot = m_lastSlice.worldRot + m_tmpl.antRots[i] + m_tmpl.fov / 2;
			ushort[] beams = m_lastSlice.data[i].beams;
			foreach (int j, ushort ilevel; beams)
			{
				ushort ilevelPrev = j > 0 ? beams[j - 1] : ushort.max;
				ushort ilevelNext = j < beams.length - 2 ? beams[j + 1] : ushort.max;
				if (ilevel > (m_min + DETECT_MARGIN) &&
					ilevel >= ilevelPrev && ilevel > ilevelNext)
				{
					// we've found the peak
					double beamRot = andLeftWrot -
						(j + 0.5f) * (m_tmpl.fov / beamCount);
					m_peaks ~= beamRot;
				}
			}
		}
		trace("current peaks: ", m_peaks);
	}
}