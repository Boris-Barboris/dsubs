module dsubs_client.core.utils;

import std.algorithm;
import std.container.array;
import std.range;


// Mixins to reduce boilerplate in object hierarchies

/** Generates final getter and virtual setter properties.
postupdateCode in injected right after field value update.
member field is expected to be named "m_" ~ fieldName, as in
hungarian scope notation. */
mixin template GetSet(T, string fieldName, string postupdateCode)
{
	mixin("final @property " ~ T.stringof ~ " " ~ fieldName ~
		"() const { return m_" ~ fieldName ~ ";};");
	mixin("@property " ~ T.stringof ~ " " ~ fieldName ~ "(" ~ T.stringof ~ " rhs) " ~
		"{ m_" ~ fieldName ~ " = rhs;" ~ postupdateCode ~ "return m_" ~ fieldName  ~ ";}");
}

/// Append additional postupdateCode to setter of the base class
mixin template OverrideSet(T, string fieldName, string postupdateCode)
{
	mixin("alias " ~ fieldName ~ " = super." ~ fieldName ~ ";");
	mixin("override @property " ~ T.stringof ~ " " ~ fieldName ~ "(" ~ T.stringof ~ " rhs) " ~
		"{ super." ~ fieldName ~ " = rhs;" ~ postupdateCode ~ "return m_" ~ fieldName ~ ";}");
}

/// Replace postupdateCode in setter of the base class
mixin template RewriteSet(T, string fieldName, string postupdateCode)
{
	mixin("alias " ~ fieldName ~ " = super." ~ fieldName ~ ";");
	mixin("override @property " ~ T.stringof ~ " " ~ fieldName ~ "(" ~ T.stringof ~ " rhs) " ~
		"{ m_" ~ fieldName ~ " = rhs;" ~ postupdateCode ~ "return m_" ~ fieldName ~ ";}");
}


/// Remove elements of range from array
void substract(T, Range)(ref Array!T arr, Range range)
{
	size_t i = 0;
	size_t shift = 0;
	while (i < arr.length - shift)
	{
		bool found = canFind(range, arr[i]);
		if (found)
			shift++;
		if (shift > 0)
			arr[i] = arr[i + shift];
		if (!found)
			i++;
	}
	arr.length = arr.length - shift;
}

unittest
{
	auto arr = Array!int(0, 1, 2 ,3);
	arr.substract([0]);
	assert(arr[].equal([1, 2, 3]));
	assert(arr.length == 3);
}
