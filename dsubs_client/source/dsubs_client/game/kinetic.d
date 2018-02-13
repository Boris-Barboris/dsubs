module dsubs_client.game.kinetic;

import std.algorithm: min;

import dsubs_common.api;
import dsubs_common.math;



/// gfm-vectored adaptaion of KinematicSnapshot
struct BodySnapshot
{
	usecs_t atTime;
	vec2d position;
	double rotation;
	double speed;
}


/// Trace of rigid body kinematics that is updated periodically from the server
/// and is being interpolated on the client for smooth rendering purposes.
/// https://en.wikipedia.org/wiki/Cubic_Hermite_spline
struct KinematicTrace
{
	private
	{
		immutable int maxLen = 3;

		// most recent snapshots received
		BodySnapshot[maxLen] trace;
		// number of actual snapshots in trace, from 0 to 3
		int len = 0;
		// index of the oldest snapshot in the trace
		int oldest = 0;
		// client-side interpolated state
		BodySnapshot curState;
		usecs_t curTime;
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
			curTime = curState.atTime;
			trace[oldest] = cast(BodySnapshot) snapshot;
			oldest = newOldest;
		}
		else
		{
			trace[(oldest + len) % maxLen] = cast(BodySnapshot) snapshot;
			len++;
		}
	}

	/// result of an interpolation
	@property BodySnapshot result() const
	{
		assert(canInterpolate);
		return curState;
	}

	/// the most recent snapshot received
	@property BodySnapshot mostRecent() const
	{
		assert(canInterpolate);
		return trace[(oldest + len) % maxLen];
	}

	/// move time forward by 'usecs' microsecods and recalculate state
	void moveForward(usecs_t fwd)
	{
		if (len < 2)	// one snapshot is not enough
			return;
		curTime = min(curTime + fwd, mostRecent.atTime);
		// now we just need to find, between which points does the
		// curTime lie
		if (len > 2)
		{
			// there is a choice here
			if (curTime <= trace[(oldest + 1) % len].atTime)
				updateResult(oldest, (oldest + 1) % len);
			else
				updateResult((oldest + 1) % len, (oldest + 2) % len);
		}
		else
		{
			// there is only one interval
			updateResult(oldest, (oldest + 1) % len);
		}
	}

	private void updateResult(int i1, int i2)
	{
		double t = (curTime - trace[i1].atTime) /
			cast(double)(curTime[i2].atTime - curTime[i1].atTime);
		double t_2 = t * t;
		double t_3 = t_2 * t;
		curState.position = (2 * t_3 - 3 * t_2 + 1) * curTime[i1].position +
			(t_3 - 2 * t_2 + t) * curTime[i1].speed
	}

}