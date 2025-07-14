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

/// Common import for all server code.

module dsubs_server.common;

public import std.algorithm: map, filter;
public import std.array: array;
public import std.algorithm.comparison: min, max;
public import std.exception: enforce;
public import std.conv: to;
public import std.math;

public import gfm.math.vector;

public import dsubs_common.api.constants: usecs_t;
public import dsubs_common.utils;
public import dsubs_common.math: clamp, Transform2D;

public import dsubs_server.rng;
public import dsubs_server.globals;


alias ObjVerT = uint;


class VersionedObject
{
	private ObjVerT m_objVersion;

	final @property ObjVerT objVersion() const { return m_objVersion; }

	final protected void bumpObjVersion()
	{
		assert(m_objVersion != ObjVerT.max);
		m_objVersion++;
	}
}


private string baseName(ClassInfo classinfo)
{
	import std.array;
	import std.algorithm : countUntil;
	import std.range : retro;

	string qualName = classinfo.name;

	ptrdiff_t dotIndex = qualName.retro.countUntil('.');

	if (dotIndex < 0) {
		return qualName;
	}

	return qualName[$ - dotIndex .. $];
}


string classBaseName(Object instance)
{
	if (instance is null) {
		return "null";
	}

	return instance.classinfo.baseName;
}