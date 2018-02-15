module dsubs_server.common;

public import std.exception;
public import std.conv: to;
public import std.experimental.logger: info, trace, error;
public import std.math;
import std.datetime;

public import dsubs_common.api.constants: usecs_t;


/// get current time in microseconds since Unix epoch.
usecs_t getCurTime()
{
	SysTime cur_time = Clock.currTime(UTC());
	auto unix_time = cur_time.toUnixTime();
	long seconds = to!long(unix_time);
	Duration frac_sec = cur_time.fracSecs;
	usecs_t usecs = frac_sec.total!"usecs";
	return seconds * 1_000_000 + usecs;
}