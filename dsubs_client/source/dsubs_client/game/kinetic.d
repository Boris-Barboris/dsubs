module dsubs_client.game.kinetic;

import dsubs_common.api;
import dsubs_common.math;


/// Trace of rigid body kinematics that is updated periodically from the server
/// and is being interpolated on the client in smooth rendering purposes.
/// https://en.wikipedia.org/wiki/Cubic_Hermite_spline
struct KinematicTrace
{
	private
	{
		immutable size_t maxLen = 3;

		// most recent snapshots received
		KinematicSnapshot[maxLen] trace;
		// number of actual snapshots in trace, from 0 to 3
		size_t len = 0;
		// index of the oldest snapshot in the trace
		size_t oldest = 0;
		// client-side interpolated state
		KinematicSnapshot curState;
	}

	@property bool canInterpolate() const { return len > 0; }

	/// Append new snapshot to the trace. If the internal buffer overflows,
	/// current state jumps forward.
	void appendSnapshot(KinematicSnapshot snapshot)
	{
		if (len == maxLen)
		{
			size_t newOldest = oldest+1 % maxLen;
			curState = trace[newOldest];
			trace[oldest] = snapshot;
			oldest = newOldest;
		}
		else
		{
			trace[oldest + len % maxLen] = snapshot;
			len++;
		}
	}
}