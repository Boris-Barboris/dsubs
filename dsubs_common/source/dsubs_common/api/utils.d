module dsubs_common.api.utils;

import std.conv;
import std.traits;
import std.meta;

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

/// Reflection-friendly POD vector. Needed because gfm vector uses anonymous union
/// wich i don't even want to bother to reflect correctly
struct PODVector(T, size_t size)
{
	T[size] data;

	this(T...)(T args)
		if (T.length == size)
	{
		foreach (i, arg; args)
			data[i] = arg;
	}

	/// reinterpret cast to gfm vector
	Vector!(T, size) toGfm() const
	{
		return *cast(Vector!(T, size)*) &this;
	}
}

alias Vector2f = PODVector!(float, 2);
alias Vector2d = PODVector!(double, 2);