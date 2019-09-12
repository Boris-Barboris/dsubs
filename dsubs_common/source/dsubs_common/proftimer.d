module dsubs_common.proftimer;

import core.time;
import std.stdio;

import dsubs_common.utils;


/// Simple cooperative profiling struct
final class ProfTimer
{
	alias TimeT = typeof(MonoTime.currTime());

	private struct Interval
	{
		string name;
		TimeT start;
		TimeT end;
	}

	private
	{
		Interval total;
		Interval[] subStack;
		Interval[] readySubIntervals;
		int lastUnclosed = -1;
	}

	void start()
	{
		total.start = MonoTime.currTime();
		readySubIntervals.length = 0;
	}

	void start(string name)
	{
		Interval newInt = Interval(name, MonoTime.currTime());
		subStack ~= newInt;
	}

	void stopLast()
	{
		assert (subStack.length > 0);
		subStack[$-1].end = MonoTime.currTime();
		readySubIntervals ~= subStack[$-1];
		subStack.length--;
	}

	void stop()
	{
		total.end = MonoTime.currTime();
		subStack.length = 0;
	}

	void printResult()
	{
		foreach (pair; readySubIntervals)
		{
			trace("ProfTimer: ", pair.name, " ",
				(pair.end - pair.start).total!"usecs", "usecs");
		}
		trace("ProfTimer total: ", (total.end - total.start).total!"usecs", "usecs");
	}

	auto getTotalUsecs() const
	{
		return (total.end - total.start).total!"usecs";
	}
}