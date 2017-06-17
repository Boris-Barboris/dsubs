module dsubs_common.api.utils;

import std.conv;
import std.traits;

import gfm.math.vector;

import dsubs_common.api.constants;
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

/// mixin to reduce line count for units that simply pass one value
mixin template SingleValueUnit(string unitname, FieldType, string fieldname)
{
	mixin("struct " ~ unitname ~ " { " ~ FieldType.stringof ~
		" " ~ fieldname ~ ";}");
}

// same but with id
mixin template IdAndValueUnit(string unitname, FieldType, string fieldname)
{
	mixin("struct " ~ unitname ~ " { ID_TYPE id; " ~ FieldType.stringof ~
		" " ~ fieldname ~ ";}");
}

/// Reflection-friendly vector type
struct Vector2(T)
{
	T x;
	T y;
	static if (is(T == float))
	{
		vec2f togfm() const pure
		{
			return vec2f(x, y);
		}
	}
	static if (is(T == double))
	{
		vec2d togfm() const pure
		{
			return vec2d(x, y);
		}
	}
}
