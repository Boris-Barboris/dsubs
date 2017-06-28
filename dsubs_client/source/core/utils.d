module dsubs_client.core.utils;

import std.algorithm;
import std.container.array;
import std.range;


/// Mixins to reduce boilerplate in object hierarchies

mixin template ElementAccessor(ElType, T, string field_name, string postupdate_code)
{
	mixin(T.stringof ~ " " ~ field_name ~ "() { return _" ~ field_name ~ ";};");
	mixin(ElType.stringof ~ " " ~ field_name ~ "(" ~ T.stringof ~ " val) " ~
		"{ _" ~ field_name ~ "=val;" ~ postupdate_code ~ "return this;}");
}

mixin template SuperAccessor(ElType, T, string field_name, string postupdate_code)
{
	mixin("override " ~ T.stringof ~ " " ~ field_name ~
		"() { return _" ~ field_name ~ ";};");
	mixin("override " ~ ElType.stringof ~ " " ~ field_name ~ "(" ~ T.stringof ~ " val) " ~
		"{ super." ~ field_name ~ "(val);" ~ postupdate_code ~ "return this;}");
}

mixin template OverrideAccessor(ElType, T, string field_name, string postupdate_code)
{
	mixin("override " ~ T.stringof ~ " " ~ field_name ~
		"() { return _" ~ field_name ~ ";};");
	mixin("override " ~ ElType.stringof ~ " " ~ field_name ~ "(" ~ T.stringof ~ " val) " ~
		"{ _" ~ field_name ~ "=val;" ~ postupdate_code ~ "return this;}");
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
