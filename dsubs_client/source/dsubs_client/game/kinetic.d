module dsubs_client.game.kinetic;

import std.algorithm: min;
import std.conv: to;
import std.experimental.logger;

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
		BodySnapshot[maxLen] records;
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
			if (curTime < records[newOldest].atTime)
			{
				// render loop is too slow, we need to push this body forward in time
				// to keep up with the stream of updates coming from the server

				// current interpolated state is behind the snapshot
				// wich will be the new oldest one
				curState = records[newOldest];
				curTime = curState.atTime;
			}
			records[oldest] = *cast(BodySnapshot*) &snapshot;
			oldest = newOldest;
		}
		else
		{
			if (len == 0)
			{
				curTime = snapshot.atTime;
				curState = *cast(BodySnapshot*) &snapshot;
			}
			records[(oldest + len) % maxLen] = *cast(BodySnapshot*) &snapshot;
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
		return records[(oldest + len - 1) % maxLen];
	}

	/// move time forward by 'usecs' microsecods and recalculate state
	void moveForward(usecs_t fwd)
	{
		if (len < 2)	// one snapshot is not enough
			return;
		curTime = min(curTime + fwd, mostRecent.atTime);
		// now we just need to find, between which points does the
		// curTime lie
		for (int curSecond = 1; curSecond < len; curSecond++)
		{
			int i2 = (oldest + curSecond) % maxLen;
			if (curTime <= records[i2].atTime)
			{
				updateResult((oldest + curSecond - 1) % maxLen, i2);
				break;
			}
			assert(curSecond != maxLen - 1, "Impossible, should be unreachable");
		}
		curState.atTime = curTime;
	}

	private void updateResult(int i1, int i2)
	{
		double dt = (records[i2].atTime - records[i1].atTime) / 1e6;
		double t = (curTime - records[i1].atTime) / 1e6 / dt;
		assert(t >= 0.0 && t <= 1.0);
		double t_2 = t * t;
		double t_3 = t_2 * t;

		auto chspline(T)(T p0, T p1, T m0, T m1)
		{
			return (2 * t_3 - 3 * t_2 + 1) * p0 +
			(t_3 - 2 * t_2 + t) * dt * m0 +
			(-2 * t_3 + 3 * t_2) * p1 +
			(t_3 - t_2) * dt * m1;
		}

		curState.position = chspline(records[i1].position, records[i2].position,
			records[i1].velocity, records[i2].velocity);
		// rotations must be moved to one half-circle in order to prevent "flips"
		curState.rotation = chspline(records[i1].rotation, records[i1].rotation +
			angleDist(records[i2].rotation, records[i1].rotation),
			records[i1].angVel, records[i2].angVel);
		// simple linear interpolation for velocities
		curState.velocity = records[i1].velocity +
			t * (records[i2].velocity - records[i1].velocity);
		curState.angVel = records[i1].angVel +
			t * (records[i2].angVel - records[i1].angVel);
	}

}