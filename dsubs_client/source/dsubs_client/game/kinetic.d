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
		immutable int maxLen = 3;

		// most recent snapshots received
		KinematicSnapshot[maxLen] trace;
		// number of actual snapshots in trace, from 0 to 3
		int len = 0;
		// index of the oldest snapshot in the trace
		int oldest = 0;
		// index of a current base snapshot
		int curBase = 0;
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
			int newOldest = (oldest + 1) % maxLen;
			curState = trace[newOldest];
			curBase = (curBase + 1) % maxLen;
			trace[oldest] = snapshot;
			oldest = newOldest;
		}
		else
		{
			trace[(oldest + len) % maxLen] = snapshot;
			len++;
		}
	}

	/// result of an interpolation
	@property KinematicSnapshot result() const
	{
		assert(canInterpolate);
		return curState;
	}

	/// the most recent snapshot received
	@property KinematicSnapshot mostRecent() const
	{
		assert(canInterpolate);
		return trace[(oldest + len) % maxLen];
	}

	/// move time forward by 'usecs' microsecods and recalculate state
	void moveForward(usecs_t fwd)
	{
		assert(fwd < 1_000_000, "Extreme lag, something is wrong in rendering loop");
		if (len < 2)	// one snapshot is not enough
			return;
		int curNextSpap = (curBase + 1) % maxLen;
		usecs_t leftover = trace[curNextSpap].atTime - curState.atTime;
		if (leftover < 0)
		{
			// we must move past the next snapshot
			if (len > 2)
			{
				// next interval is indeed availiable
			}
		}
	}
}