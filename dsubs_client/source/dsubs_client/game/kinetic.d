module dsubs_client.game.kinetic;

import std.algorithm: min;
import std.conv: to;
import std.experimental.logger;

import dsubs_common.api;
import dsubs_common.math;



/// Trace of rigid body kinematics that is updated periodically from the server
/// and is being interpolated on the client for smooth rendering purposes.
/// https://en.wikipedia.org/wiki/Cubic_Hermite_spline
struct KinematicTrace
{
	private
	{
		immutable int maxLen = 3;

		// most recent snapshots received
		KinematicSnapshot[maxLen] records;
		// number of actual snapshots in trace, from 0 to 3
		int len = 0;
		// index of the oldest snapshot in the trace
		int oldest = 0;
		// client-side interpolated state
		KinematicSnapshot curState;
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
			records[oldest] = *cast(KinematicSnapshot*) &snapshot;
			oldest = newOldest;
		}
		else
		{
			if (len == 0)
			{
				curTime = snapshot.atTime;
				curState = *cast(KinematicSnapshot*) &snapshot;
			}
			records[(oldest + len) % maxLen] = *cast(KinematicSnapshot*) &snapshot;
			len++;
		}
	}

	/// result of an interpolation
	@property ref const(KinematicSnapshot) result() const
	{
		assert(canInterpolate);
		return curState;
	}

	/// the most recent snapshot received
	@property ref const(KinematicSnapshot) mostRecent() const
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

		curState.position = chspline(records[i1].position, records[i2].position,
			records[i1].velocity, records[i2].velocity, t, dt);
		curState.rotation = chspline(records[i1].rotation, records[i2].rotation,
			records[i1].angVel, records[i2].angVel, t, dt);
		// simple linear interpolation for velocities
		curState.velocity = records[i1].velocity +
			t * (records[i2].velocity - records[i1].velocity);
		curState.angVel = records[i1].angVel +
			t * (records[i2].angVel - records[i1].angVel);
	}

}