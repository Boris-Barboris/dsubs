// All API units are registered in this module. Functions to marhal
// and demarshal them into byte streams are generated here too.

module dsubs_common.api.marshallers;

import std.algorithm.comparison;
import std.algorithm.searching;
import std.conv;
import std.meta;
import std.traits;

import dsubs_common.api.utils;
import dsubs_common.math.hash;
import dsubs_common.reflection;

import dsubs_common.api.auth;
import dsubs_common.api.status;

// List should be filled with names of all dsubs API units
public immutable string[] api_units = [
	"ServerStatusRequest",
	"ServerStatusResponse",
	"DisconnectSignal",
	"AuthLoginRequest",
	"RegisterRequest",
	"RegisterResponse",
];

alias Demarshaller = void* function(ubyte[] data, out uint shift);
alias Marshaller = uint function(const void* ptr, ubyte[] stream);
alias header_t = ulong;
enum HEADER_SIZE = header_t.sizeof;

/// Global hash-map of demarshalling functions
immutable Demarshaller[header_t] demarshallers;

/// Marshall API unit into byte stream
uint marshal(T)(const T* ptr, ubyte[] stream)
	if (canFind(api_units, T.stringof))
{
	pragma(msg, "Generating marshaller for ", T.stringof);
	return GenericStructMarshaller!(T).marshal(ptr, stream);
}

static this()
{
	foreach (unit_type_str; aliasSeqOf!api_units)
	{
		// generate marshaller
		enum unit_hash = djb2(unit_type_str);
		pragma(msg, "Generating demarshaller for ", unit_type_str);
		demarshallers[unit_hash] =
			cast(Demarshaller) &(GenericStructMarshaller!(mixin(unit_type_str)).demarshal);
	}
}

unittest
{
	struct Struct1
	{
		ubyte sign;
		string msg;
	}
	struct Struct2
	{
		Struct1[] arr;
	}

	ubyte[] stream = new ubyte[512];
	Struct2 s2 = Struct2([Struct1(2, "msg1"), Struct1(5, "msg2")]);
	uint shift1 = GenericStructMarshaller!(Struct2).marshal(&s2, stream);
	stream = stream[header_t.sizeof .. $];
	uint shift2;
	Struct2* s2d = GenericStructMarshaller!(Struct2).demarshal(stream, shift2);
	assert(shift2 == shift1 - header_t.sizeof);
	assert(s2d.arr.length == 2);
	assert(s2d.arr[0].sign == 2);
	assert(s2d.arr[1].sign == 5);
	assert(s2d.arr[0].msg == "msg1");
	assert(s2d.arr[1].msg == "msg2");
}

//
// Marshalling code generators
//

// This generator operates on nested structs, wich can include arrays
// of primitive scalar types or other structs. Pointes are not allowed.
template GenericStructMarshaller(T)
	if (is(T == struct))
{
	uint marshal(const(T)* ptr, ubyte[] stream)
	{
		uint shift = HEADER_SIZE;
		enum header = djb2(T.stringof);
		header_t* header_pos = cast(header_t*) stream.ptr;
		*header_pos = header;
		stream = stream[HEADER_SIZE .. $];
		return shift + do_marshal!(const(T))(ptr, stream);
	}

	T* demarshal(const(ubyte)[] stream, out uint shift)
	{
		T* ptr = new T();
		shift = do_demarshal!(T)(ptr, stream);
		return ptr;
	}
}

uint do_marshal(StructType)(StructType* ptr, ubyte[] stream)
	if (is(StructType == struct))
{
	uint shift = 0;
	enum fields = TypeMembers!(StructType, FieldFlags.Fields)();
	foreach (field; aliasSeqOf!(fields))
	{
		alias FieldType = typeof(mixin("ptr." ~ field));
		uint field_shift = do_marshal!(StructType, FieldType, field)(ptr, stream);
		stream = stream[field_shift .. $];
		shift += field_shift;
	}
	return shift;
}

uint do_demarshal(StructType)(StructType* ptr, const(ubyte)[] stream)
	if (is(StructType == struct))
{
	uint shift = 0;
	enum fields = TypeMembers!(StructType, FieldFlags.Fields)();
	foreach (field; aliasSeqOf!(fields))
	{
		alias FieldType = typeof(mixin("ptr." ~ field));
		uint field_shift = do_demarshal!(StructType, FieldType, field)(ptr, stream);
		stream = stream[field_shift .. $];
		shift += field_shift;
	}
	return shift;
}

uint do_marshal(StructType, SubArrayType, string FieldName)(StructType* ptr, ubyte[] stream)
	if (is(StructType == struct) && isArray!(SubArrayType))
{
	uint shift = 0;
	// check for UDA's altering max length
	enum attrs = FieldAttributes!(StructType, FieldName);
	uint max_length = DEFAULT_MAX_ARRAY_LENGTH;
	foreach (attr; attrs)
	{
		static if (is(typeof(attr) == MaxLenAttr))
			max_length = attr.max_length;
	}
	// serialize array size
	SubArrayType arr = mixin("ptr." ~ FieldName);
	if (arr.length > max_length)
		throw new MaxLenExceeded(arr.length, max_length);
	uint* len_ptr = cast(uint*) stream.ptr;
	*len_ptr = arr.length;
	stream = stream[uint.sizeof .. $];
	shift += uint.sizeof;
	// serialize array
	alias ElType = ArrayElementType!SubArrayType;
	static if (isScalarType!ElType)
	{
		alias UqElType = Unqual!ElType;
		// array of scalar types
		shift += UqElType.sizeof * arr.length;
		UqElType* dest_ptr = cast(UqElType*) stream.ptr;
		for (uint i = 0; i < arr.length; i++, dest_ptr++)
			*dest_ptr = arr[i];
	}
	else static if (is(ElType == struct))
	{
		// array of structs
		foreach (ElType el; arr)
		{
			uint field_shift = do_marshal!(ElType)(&el, stream);
			stream = stream[field_shift .. $];
			shift += field_shift;
		}
	}
	else static assert(0, "unsupported array type");
	return shift;
}

uint do_demarshal(StructType, SubArrayType, string FieldName)(StructType* ptr, const(ubyte)[] stream)
	if (is(StructType == struct) && isArray!(SubArrayType))
{
	uint shift = 0;
	// check for UDA's altering max length
	enum attrs = FieldAttributes!(StructType, FieldName);
	uint max_length = DEFAULT_MAX_ARRAY_LENGTH;
	foreach (attr; attrs)
	{
		static if (is(typeof(attr) == MaxLenAttr))
			max_length = attr.max_length;
	}
	// deserialize array size
	uint arr_length = *(cast(uint*) stream.ptr);
	if (arr_length > max_length)
		throw new MaxLenExceeded(arr_length, max_length);
	alias ElType = ArrayElementType!SubArrayType;
	alias UqElType = Unqual!ElType;
	UqElType[] arr;
	arr.length = arr_length;
	stream = stream[uint.sizeof .. $];
	shift += uint.sizeof;
	// serialize array
	static if (isScalarType!ElType)
	{
		// array of scalar types
		shift += ElType.sizeof * arr.length;
		const(ElType)* src_ptr = cast(const(ElType)*) stream.ptr;
		for (uint i = 0; i < arr.length; i++, src_ptr++)
			arr[i] = *src_ptr;
	}
	else static if (is(ElType == struct))
	{
		// array of structs
		UqElType* dst_ptr = arr.ptr;
		for (uint i = 0; i < arr.length; i++, dst_ptr++)
		{
			uint field_shift = do_demarshal!(ElType)(dst_ptr, stream);
			stream = stream[field_shift .. $];
			shift += field_shift;
		}
	}
	else static assert(0, "unsupported array type");
	mixin("ptr." ~ FieldName) = cast(SubArrayType) arr;
	return shift;
}

uint do_marshal(StructType, SubstructType, string FieldName)(StructType* ptr, ubyte[] stream)
	if (is(StructType == struct) && is(SubstructType == struct))
{
	uint shift = 0;
	enum subfields = TypeMembers!(SubstructType, FieldFlags.Fields)();
	const(SubstructType)* subptr = mixin("&(ptr." ~ FieldName ~ ")");
	foreach (subfield; aliasSeqOf!(subfields))
	{
		alias SubfieldType = typeof(mixin("ptr." ~ FieldName ~ "." ~ subfield));
		uint field_shift = do_marshal!(SubstructType, SubfieldType, subfield)(subptr, stream);
		stream = stream[field_shift .. $];
		shift += field_shift;
	}
	return shift;
}

uint do_demarshal(StructType, SubstructType, string FieldName)(StructType* ptr, const(ubyte)[] stream)
	if (is(StructType == struct) && is(SubstructType == struct))
{
	uint shift = 0;
	enum subfields = TypeMembers!(SubstructType, FieldFlags.Fields)();
	SubstructType* subptr = mixin("&(ptr." ~ FieldName ~ ")");
	foreach (subfield; aliasSeqOf!(subfields))
	{
		alias SubfieldType = typeof(mixin("ptr." ~ FieldName ~ "." ~ subfield));
		uint field_shift = do_demarshal!(SubstructType, SubfieldType, subfield)(subptr, stream);
		stream = stream[field_shift .. $];
		shift += field_shift;
	}
	return shift;
}

uint do_marshal(StructType, FieldType, string FieldName)(StructType* ptr, ubyte[] stream)
	if (is(StructType == struct) && isScalarType!FieldType)
{
	Unqual!(FieldType)* dest_ptr = cast(Unqual!(FieldType)*) stream.ptr;
	*dest_ptr = mixin("ptr." ~ FieldName);
	return FieldType.sizeof;
}

uint do_demarshal(StructType, FieldType, string FieldName)(StructType* ptr, const(ubyte)[] stream)
	if (is(StructType == struct) && isScalarType!FieldType)
{
	const(FieldType)* source_ptr = cast(const(FieldType)*) stream.ptr;
	mixin("ptr." ~ FieldName) = *source_ptr;
	return FieldType.sizeof;
}
