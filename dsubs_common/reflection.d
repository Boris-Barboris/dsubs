module reflection;

import std.array;
import std.algorithm;
import std.meta;
import std.traits;


enum FieldFlags: byte
{
	Fields = 0,			// by default simply return all underived fields
	Derived = 1,		// return base type fields
	Underscored = 2,	// members with names starting from undesrcore
	Functions = 4,		// return functions of any kind
}

template isNotUnderscoreStarted(string name)
{
	enum isNotUnderscoreStarted = !(name[0] == '_');
}

template UnderscoreFilter(FieldFlags flags, TList...)
{
	static if (!(flags & FieldFlags.Underscored))
		enum UnderscoreFilter = Filter!(isNotUnderscoreStarted, TList);
	else
		enum UnderscoreFilter = TList;
}

string[] stringSetIntersect(string[] A, string[] B)()
{
	string[] result = [];
	foreach (s; aliasSeqOf!(A))
	{
		enum in_B = find(B, s);
		if (in_B)
			result ~= s;
	}
	return result;
}

template DerivedFilter(T, FieldFlags flags, TList...)
{
	static if (flags & FieldFlags.Derived)
		enum DerivedFilter = TList;
	else
	{
		enum str_diff = stringSetIntersect!([TList], 
											[__traits(derivedMembers, T)])();
		enum DerivedFilter = aliasSeqOf!(str_diff);
	}
}

template isFunctionName(T)
{
	template isFuncField(string name)
	{
		alias isFuncField = isFunction!(mixin("T." ~ name));
	}
}

template FunctionalMembersFilter(T, FieldFlags flags, TList...)
{
	static if (flags & FieldFlags.Functions)
		enum FunctionalMembersFilter = TList;
	else
		enum FunctionalMembersFilter = 
			Filter!(templateNot!(isFunctionName!(T).isFuncField), TList);
}

/// Return array of T members, that match the criteria
string[] TypeMembers(T, FieldFlags flags)() if (isAggregateType!(T))
{
	enum field_names = __traits(allMembers, T);
	enum underscore_filtered = UnderscoreFilter!(flags, field_names);
	enum derived_filtered = DerivedFilter!(T, flags, underscore_filtered);
	enum function_filtered = FunctionalMembersFilter!(T, flags, derived_filtered);
	return [function_filtered];
}

/// Returns tumple of attributes
template FieldAttributes(T, string field_name)
{
	enum FieldAttributes = __traits(getAttributes, mixin("T." ~ field_name));
}