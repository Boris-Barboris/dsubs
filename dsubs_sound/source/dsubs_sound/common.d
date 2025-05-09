/*
DSubs
Copyright (C) 2017-2025 Baranin Alexander

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
module dsubs_sound.common;

public import std.conv: to;
public import std.exception: enforce;
public import std.experimental.logger: trace, error;
public import std.numeric;
public import std.complex;
public import std.math;
import std.random;

public import dsubs_common.math;

public import dsubs_sound.units;
public import dsubs_sound.opencl: DsubsSoundOpenclCtx;


pragma(inline)
auto uniform(string boundaries = "[]", T1, T2)(T1 a, T2 b)
{
	return std.random.uniform!(boundaries, T1, T2)(a, b, rndGen);
}

pragma(inline)
auto uniform01(T)()
{
	return uniform!("[]", T, T)(0.0, 1.0);
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