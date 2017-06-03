module dsubs_common.api.utils;

import std.conv;
import std.traits;

import dsubs_common.reflection;

// yes, uint, no 4GB+ arrays over TCP please
immutable uint DEFAULT_MAX_ARRAY_LENGTH = 1024;

/// UDA to decorate arrays and specify upper length limit
struct MaxLenAttr
{
	uint max_length = DEFAULT_MAX_ARRAY_LENGTH;
}

class MaxLenExceeded: Exception
{
	uint actual_length;
	uint max_length;
	this(uint actual, uint max)
	{
		super("max length " ~ to!string(max) ~ " , actual " ~ to!string(actual));
		this.actual_length = actual;
		this.max_length = max;
	}
}

template ArrayElementSize(T) if (isArray!T)
{
	enum ArrayElementSize = (ArrayElementType!T).sizeof;
}
