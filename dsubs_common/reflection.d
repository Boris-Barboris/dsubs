module reflection;

import std.array;
import std.algorithm;
import std.meta;
import std.traits;


private immutable string[] si = ["abc", "defg"];

private immutable(string[]) ctfe_filter_test(immutable string[] arr, string filt)
{
	auto res = filter!(a => a == filt)(arr).array;
	return res;
}

private struct TestReflectionStruct
{
	int field1;
	int field2;
}

bool ctfe_is_field(T, string field_name)()
{
	//return !isFunction(mixin(T.stringof ~ "." ~ field_name));
	return !(isFunction!(__traits(getMember, T, field_name)));
}

private string[] ctfe_leave_fields(T, string[] field_names)()
{
	string[] ok;
	foreach (name; aliasSeqOf!field_names)
		if (ctfe_is_field!(T, name)())
			ok ~= field_names[0];
	return ok;
}

private string[] ctfe_field_test(T)()
{
	enum field_names = [__traits(allMembers, T)];
	auto field_names2 = ctfe_leave_fields!(T, field_names)();
	return field_names2;
}


unittest
{
	enum filtered = ctfe_field_test!(TestReflectionStruct)();
	pragma(msg, "unittest ", typeof(filtered), " ", filtered);
}


enum FieldFlags: byte
{
	Fields = 0,		// by default simply return only fields
	Derived = 1,	// return base type fields
	Underscored = 2,	// members with names starting from undesrcore
	Functions = 8,	// return functions of any kind
}

template isFunctionField(OwnerType, string field_name)
{
	enum isFunctionField = 
		isFunction(mixin(OwnerType.stringof ~ "." ~ field_name));
}

bool isFunctionFieldFunc(OwnerType)(string field_name)
{
	return true;//isFunction(mixin(OwnerType.stringof ~ "." ~ field_name));
}

string[] sfilter(T)(string[] fields)
{
	string[] result;
	for (int i = 0; i < fields.length; i++)
	{
		auto f = fields[i];
		enum isfunc = isFunctionFieldFunc!(T)(f);
		if (isfunc)
			result ~= f;
	}
	return result;
}

/// Return array of field names, that match the criteria
string[] TypeFields(T, FieldFlags flags)() pure
{
	enum field_names = [__traits(allMembers, T)];
	//pragma(msg, field_names.length);
	//foreach (name; _field_names)
	//	field_names ~= name;
	//string[] field_names = ["global_option1"];
	//string[] field_names = _field_names.dup;
	// now let's filter the array
	//if (!(flags & FieldFlags.Underscored))
	//{
	//    // remove service fields
	//    field_names = remove!(a => a[0] == '_')(field_names);
	//}
	// filter out derived fields if needed
	//if (!(flags & FieldFlags.Derived))
	//{
	//    string[] derived_field_names = [__traits(derivedMembers, T)];
	//    field_names = remove!(a => !(canFind(derived_field_names, a)))
	//                        (field_names);
	//}
	pragma(msg, typeof(field_names));
	pragma(msg, field_names);

	enum filtered = sfilter!(T)(field_names);

	//enum filtered = getFunctionMembers!(T)(field_names);
	//
	//pragma(msg, typeof(filtered));
	//pragma(msg, filtered);
	//if (!(flags & FieldFlags.Functions))
	//{
	//    string[] filtered_names;
	//    foreach (field; field_names)
	//        if (!isFunctionField!(T, field))
	//            filtered_names ~= field;
	//    field_names = filtered_names;
	//}
	return field_names;
}

/// Returns tumple of attributes
auto getFieldAttributes(T)(string field_name)
{
	return __traits(getAttributes, mixin(T.stringof ~ "." ~ field_name));
}