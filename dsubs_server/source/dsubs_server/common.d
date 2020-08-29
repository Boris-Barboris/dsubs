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
public import dsubs_common.math: clamp;

public import dsubs_server.rng;
public import dsubs_server.globals;


alias ObjVer = uint;


class VersionedObject
{
	private ObjVer m_objVersion;

	@property ObjVer objVersion() const { return m_objVersion; }

	final protected void bumpObjVersion()
	{
		assert(m_objversion != ObjVer.max);
		m_objversion++;
	}
}