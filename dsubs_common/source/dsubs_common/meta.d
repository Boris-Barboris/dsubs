module dsubs_common.meta;

public import std.meta: Filter, anySatisfy, staticMap, aliasSeqOf, AliasSeq;
public import std.traits: FieldNameTuple, Unqual;
public import painlesstraits: hasAnnotation, getAnnotation;
public import std.range.primitives: ElementType;


/** Data field descriptor. */
struct FieldMeta(T, string field_name)
{
	alias type = T;
	enum name = field_name;
}


/** Query field names and types a composite (struct or class). */
template AllFields(T)
{
	private template fieldNameToMeta(string field)
	{
		alias fieldNameToMeta = FieldMeta!(typeOfMember!(T, field), field);
	}
	alias AllFields = staticMap!(fieldNameToMeta, fieldNames!T);
	static assert(AllFields.length > 0, "No fields for type " ~ T.stringof);
}


/** Defines filtering function to pass only for members with Attr UDA on them. */
template HasUdaFilter(T, alias Attr)
{
	template filter(alias field_meta)
	{
		enum filter = hasAnnotation!(__traits(getMember, T, field_meta.name), Attr);
	}
}


template HasUda(T, string field, alias Attr)
{
	enum HasUda = hasAnnotation!(__traits(getMember, T, field), Attr);
}


template GetUda(T, string field, alias Attr)
{
	enum GetUda = getAnnotation!(__traits(getMember, T, field), Attr);
}


/** Returns alias sequence of FieldMeta descriptors that have Attr UDA on them. */
template AllFieldsWithUda(T, alias Attr)
{
	alias AllFieldsWithUda = Filter!(HasUdaFilter!(T, Attr).filter, AllFields!T);
}


alias FieldNames = FieldNameTuple;


/** Returns type tuple of all T fields */
template FieldTypes(T)
{
	private template fieldToType(alias field)
	{
		alias fieldToType = typeOfMember!(T, field);
	}
	alias FieldTypes = staticMap!(fieldToType, FieldNames!T);
}


/** Returns type of the Owner field named member */
template TypeOfMember(Owner, string member)
{
	alias TypeOfMember = typeof(__traits(getMember, Owner, member));
}


/** Filter wich passes when needle is found in Haystack alias sequence */
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


/** Set intersection of alias sequences */
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