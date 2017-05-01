module dsubs_client.core.utils;

import std.algorithm;
import std.range;

import dsubs_client.containers.dlist;

unittest
{
	DList!int list = [1, 3, 1, 4];
	list.removePred(a => a == 1);
	assert(equal(list[], [3, 4]));
}


/// Mixins to reduce boilerplate in object hierarchies

mixin template ElementAccessor(ElType, T, string field_name, string update_code)
{
	mixin(T.stringof ~ " " ~ field_name ~ "() { return _" ~ field_name ~ ";};");
	mixin(ElType.stringof ~ " " ~ field_name ~ "(" ~ T.stringof ~ " val) " ~
		"{ _" ~ field_name ~ "=val;" ~ update_code ~ "return this;}");
}

mixin template SuperAccessor(ElType, T, string field_name, string update_code)
{
	mixin("override " ~ T.stringof ~ " " ~ field_name ~
		"() { return _" ~ field_name ~ ";};");
	mixin("override " ~ ElType.stringof ~ " " ~ field_name ~ "(" ~ T.stringof ~ " val) " ~
		"{ super." ~ field_name ~ "(val);" ~ update_code ~ "return this;}");
}

mixin template OverrideAccessor(ElType, T, string field_name, string update_code)
{
	mixin("override " ~ T.stringof ~ " " ~ field_name ~
		"() { return _" ~ field_name ~ ";};");
	mixin("override " ~ ElType.stringof ~ " " ~ field_name ~ "(" ~ T.stringof ~ " val) " ~
		"{ _" ~ field_name ~ "=val;" ~ update_code ~ "return this;}");
}
