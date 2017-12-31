module dsubs_common.api.utils;

import std.conv;
import std.traits;

import gfm.math.vector;

import dsubs_common.meta;

/// UDA to decorate arrays and specify upper length limit
struct MaxLenAttr
{
	int maxLength = 4096;
}

/// Thrown on marshalling\demarshalling of messages that violate array
/// length restrictions.
class MaxLenExceeded: Exception
{
	int actualLength;
	int maxLength;

	private static string getMsg(int actual, int max)
	{
		return "max length " ~ max.to!string ~ ", actual " ~ actual.to!string;
	}

	this(int actual, int max, string file = __FILE__, 
		size_t line = __LINE__, Throwable next = null)
	{
		super(getMsg(actual, max), file, line, next);
		actualLength = actual;
		maxLength = max;
	}

	this(int actual, int max, Throwable next, string file = __FILE__, 
		size_t line = __LINE__)
	{
		super(getMsg(actual, max), file, line, next);
		actualLength = actual;
		maxLength = max;
	}
}

/// Reflection-friendly POD vector type
struct Vector2(T)
{
	T x;
	T y;
}

vec2f togfm(Vector2!float v)
{
	return vec2f(v.x, v.y);
}

vec2d togfm(Vector2!double v)
{
	return vec2d(v.x, v.y);
}

vec2i togfm(Vector2!int v)
{
	return vec2i(v.x, v.y);
}