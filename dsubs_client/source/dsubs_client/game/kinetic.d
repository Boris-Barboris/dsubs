module dsubs_client.game.kinetic;

import std.algorithm: min;

import dsubs_common.api;
import dsubs_common.math;



/// adaptation of KinematicSnapshot with gfm vectors
struct BodySnapshot
{
	usecs_t atTime;
	vec2d position;
	vec2d velocity;
	double rotation;
	double angVel;
}

static assert (KinematicSnapshot.sizeof == BodySnapshot.sizeof);


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
	void appendSnapshot(ref const KinematicSnapshot snapshot)
	{
		if (len == maxLen)
		{
			int newOldest = (oldest + 1) % maxLen;
			if (curTime < trace[newOldest].atTime)
			{
				// render loop is too slow, we need to push this body forward in time
				// to keep up with the stream of updates coming from the server

				// current interpolated state is behind the snapshot
				// wich will be the new oldest one
				curState = trace[newOldest];
				curTime = curState.atTime;
			}
			trace[oldest] = *cast(BodySnapshot*) &snapshot;
			oldest = newOldest;
		}
		else
		{
			if (len == 0)
			{
				curTime = snapshot.atTime;
				curState = *cast(BodySnapshot*) &snapshot;
			}
			trace[(oldest + len) % maxLen] = *cast(BodySnapshot*) &snapshot;
			len++;
		}
	}

	/// result of an interpolation
	@property ref const(BodySnapshot) result() const
	{
		assert(canInterpolate);
		return curState;
	}

	/// the most recent snapshot received
	@property ref const(BodySnapshot) mostRecent() const
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
		curState.atTime = curTime;
	}

	private void updateResult(int i1, int i2)
	{
		double t = (curTime - trace[i1].atTime) /
			cast(double) (trace[i2].atTime - trace[i1].atTime);
		double t_2 = t * t;
		double t_3 = t_2 * t;

		auto chspline(T)(T p0, T p1, T m0, T m1)
		{
			return (2 * t_3 - 3 * t_2 + 1) * p0 +
			(t_3 - 2 * t_2 + t) * m0 +
			(-2 * t_3 + 3 * t_2) * p1 +
			(t_3 - t_2) * m1;
		}

		curState.position = chspline(trace[i1].position, trace[i2].position,
			trace[i1].velocity, trace[i2].velocity);
		curState.rotation = chspline(trace[i1].rotation, trace[i2].rotation,
			trace[i1].angVel, trace[i2].angVel);
		// simple linear interpolation for velocities
		curState.velocity = trace[i1].velocity +
			t * (trace[i2].velocity - trace[i1].velocity);
		curState.angVel = trace[i1].angVel +
			t * (trace[i2].angVel - trace[i1].angVel);
	}

}