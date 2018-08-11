module dsubs_sound.common;

public import std.conv: to;
public import std.exception: enforce;
public import std.numeric;
public import std.complex;
public import std.math;
import std.random;

public import dsubs_common.math;

public import dsubs_sound.units;

private Xorshift64 rngen;

static this()
{
	rngen = Xorshift64();
}

pragma(inline)
auto uniform(string boundaries = "[]", T1, T2)(T1 a, T2 b)
{
	return std.random.uniform!(boundaries, T1, T2)(a, b, rngen);
}

pragma(inline)
auto uniform01(T)()
{
	return std.random.uniform01!T(rngen);
}