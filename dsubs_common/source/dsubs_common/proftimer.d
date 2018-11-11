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
		TimeT start;
		TimeT end;
	}

	private
	{
		Interval total;
		Interval[string] subintervals;
		string m_last;
	}

	void start()
	{
		total.start = MonoTime.currTime();
	}

	void start(string name)
	{
		Interval newInt = Interval(MonoTime.currTime());
		subintervals[name] = newInt;
		m_last = name;
	}

	void stopLast()
	{
		assert(m_last.length > 0);
		subintervals[m_last].end = MonoTime.currTime();
		m_last = null;
	}

	void stop()
	{
		total.end = MonoTime.currTime();
		m_last = null;
	}

	void printResult()
	{
		foreach (pair; subintervals.byKeyValue)
		{
			trace("ProfTimer: ", pair.key, " ",
				(pair.value.end - pair.value.start).total!"usecs", "usecs");
		}
		trace("ProfTimer total: ", (total.end - total.start).total!"usecs", "usecs");
	}
}