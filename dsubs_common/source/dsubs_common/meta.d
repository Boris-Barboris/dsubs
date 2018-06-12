/**
D template helpers, mostly for data structure introspection.
*/

module dsubs_common.meta;

public import std.meta: Filter, anySatisfy, staticMap, aliasSeqOf, AliasSeq;
public import std.traits: FieldNameTuple, Unqual;
public import painlesstraits: hasAnnotation, getAnnotation;
public import std.range.primitives: ElementType;


/// Struct template that describes a class\struct field.
struct FieldMeta(T, string field_name)
{
	alias type = T;
	enum name = field_name;
}


/// Get tuple of FieldMeta's for a struct or class fields.
template AllFields(T)
{
	private template fieldNameToMeta(string field)
	{
		alias fieldNameToMeta = FieldMeta!(typeOfMember!(T, field), field);
	}
	alias AllFields = staticMap!(fieldNameToMeta, FieldNames!T);
	static assert(AllFields.length > 0, T.stringof ~ " has no field");
}


// Defines filtering function that passes only for members with Attr UDA on them.
private template HasUdaFilter(T, alias Attr)
{
	template filter(alias field_meta)
	{
		enum filter = hasAnnotation!(__traits(getMember, T, field_meta.name), Attr);
	}
}


/// True when field 'field' of type T has UDA Attr on it.
template HasUda(T, string field, alias Attr)
{
	enum HasUda = hasAnnotation!(__traits(getMember, T, field), Attr);
}

/// Gets the UDA.
template GetUda(T, string field, alias Attr)
{
	enum GetUda = getAnnotation!(__traits(getMember, T, field), Attr);
}


/// Returns alias sequence of FieldMeta's that have UDA Attr on them.
template AllFieldsWithUda(T, alias Attr)
{
	alias AllFieldsWithUda = Filter!(HasUdaFilter!(T, Attr).filter, AllFields!T);
}

/// convenience alias for std.traits.FieldNameTuple
alias FieldNames = FieldNameTuple;


/// Returns type tuple of all fields of T.
template FieldTypes(T)
{
	private template fieldToType(alias field)
	{
		alias fieldToType = typeOfMember!(T, field);
	}
	alias FieldTypes = staticMap!(fieldToType, FieldNames!T);
}

/// Returns type of the field 'field' of T.
template TypeOfMember(T, string field)
{
	alias TypeOfMember = typeof(__traits(getMember, T, field));
}


/// Filter wich passes when needle is found in Haystack alias sequence.
template CanFind(alias needle)
{
	template In(Haystack...)
	{
		private template EqualPred(alias v)
		{
			enum EqualPred = (v == needle);
		}
		enum In = anySatisfy!(EqualPred, Haystack);
	}
}

static assert (CanFind!"a".In!(AliasSeq!("b", "a")));


/// Set intersection of alias sequences.
template Intersect(T1...)
{
	template With(T2...)
	{
		private template IntersectFilt(alias val)
		{
			enum IntersectFilt = CanFind!val.In!T2;
		}
		alias With = Filter!(IntersectFilt, T1);
	}
}

static assert (Intersect!("n1", "n2").With!("n2", "n3") == AliasSeq!("n2"));

/// Size of an alement of InputRange R.
template ElementSize(R)
{
	enum ElementSize = (ElementType!R).sizeof;
}

static assert (ElementSize!(int[]) == 4);

/// type of slice element
template ArrayElementT(R)
{
	alias ArrayElementT = typeof(R.init[0]);
}

/// size of one slice element
template ArrayElementSize(R)
{
	enum ArrayElementSize = ArrayElementT!(R).sizeof;
}