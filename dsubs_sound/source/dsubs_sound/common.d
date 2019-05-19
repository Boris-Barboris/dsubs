module dsubs_sound.common;

public import std.conv: to;
public import std.exception: enforce;
public import std.experimental.logger: trace;
public import std.numeric;
public import std.complex;
public import std.math;
import std.random;

public import dsubs_common.math;

public import dsubs_sound.units;

private Xorshift64 rngen;

static this()
{
	// let's use xorshift since it's much cheaper
	rngen = Xorshift64();
}

pragma(inline)
auto uniform(string boundaries = "[]", T1, T2)(T1 a, T2 b)
{
	return std.random.uniform!(boundaries, T1, T2)(a, b, rndGen);
}

pragma(inline)
auto uniform01(T)()
{
	return std.random.uniform01!T(rndGen);
}

pragma(inline)
ulong ulongSeed()
{
	return std.random.uniform!ulong(rndGen);
}

pragma(inline)
uint uintSeed()
{
	return std.random.uniform!uint(rndGen);
}

/// dsubs_sound operates only on time-domain signals with this sampling-rate
enum GLOBAL_SRATE = 8192;