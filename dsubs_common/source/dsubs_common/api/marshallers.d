// All API units are registered in this module. Functions to marhal
// and demarshal them into byte streams are generated here too.

module dsubs_common.api.marshallers;

import std.algorithm.comparison;
import std.algorithm.searching;
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
	return ArrayAwareMarshaller!(T).marshal(ptr, stream);
}

static this()
{
	foreach (unit_type_str; aliasSeqOf!api_units)
	{
		// generate marshaller
		enum unit_hash = djb2(unit_type_str);
		pragma(msg, "Generating demarshaller for ", unit_type_str);
		demarshallers[unit_hash] =
			cast(Demarshaller) &(ArrayAwareMarshaller!(mixin(unit_type_str)).demarshal);
	}
}

//
// Marshalling code generators
//

// Can operate on structs, that contain other structs. Leaves of the tree can
// only contain primitive types. Arrays are allowed only in top-level
// struct.
template ArrayAwareMarshaller(T)
	if (is(T == struct))
{
	uint marshal(const(T)* ptr, ubyte[] stream)
	{
		uint shift = HEADER_SIZE;
		enum header = djb2(T.stringof);
		header_t* header_pos = cast(header_t*) stream.ptr;
		*header_pos = header;
		stream = stream[HEADER_SIZE .. $];
		auto struct_ptr = cast(const(ubyte)*) ptr;
		struct_ptr += HEADER_SIZE;
		// Now handle fields
		enum fields = TypeMembers!(T, FieldFlags.Fields)();
		foreach (field; aliasSeqOf!(fields))
		{
			static if (field == "header")
				continue;
			else
			{
				alias FieldType = typeof(mixin("ptr." ~ field));
				static if (isArray!FieldType)
				{
					// we're marshalling array. First we serialize it's length,
					// then it's body
					enum attrs = FieldAttributes!(T, field);
					uint max_length = DEFAULT_MAX_ARRAY_LENGTH;
					foreach (attr; attrs)
					{
						static if (is(typeof(attr) == MaxLenAttr))
							max_length = attr.max_length;
					}
					// serialize array size
					FieldType arr = mixin("ptr." ~ field);
					uint length = arr.length;
					if (length > max_length)
						throw new MaxLenExceeded(length, max_length);
					ubyte* field_ptr = cast(ubyte*) &length;
					for (uint i = 0; i < uint.sizeof; i++, field_ptr++)
						stream[i] = *field_ptr;
					stream = stream[uint.sizeof .. $];
					shift += uint.sizeof;
					// serialize array
					enum element_size = ArrayElementSize!FieldType;
					field_ptr = cast(ubyte*) arr.ptr;
					uint byte_count = element_size * length;
					for (uint i = 0; i < byte_count; i++, field_ptr++)
						stream[i] = *field_ptr;
					stream = stream[byte_count .. $];
					shift += byte_count;
				}
				else
				{
					enum field_size = FieldType.sizeof;
					FieldType val = mixin("ptr." ~ field);
					ubyte* field_ptr = cast(ubyte*) &val;
					for (uint i = 0; i < field_size; i++, field_ptr++)
						stream[i] = *field_ptr;
					stream = stream[field_size .. $];
					shift += field_size;
				}
			}
		}
		return shift;
	}


	T* demarshal(ubyte[] data, out uint shift)
	{
		uint local_shift = 0;
		auto result = new T;
		enum fields = TypeMembers!(T, FieldFlags.Fields)();
		pragma(msg, "fields =", fields)
		foreach (field; aliasSeqOf!(fields))
		{
			static if (field == "header")
				continue;
			else
			{
				alias FieldType = typeof(mixin("result." ~ field));
				static if (isArray!FieldType)
				{
					enum attrs = FieldAttributes!(T, field);
					uint max_length = DEFAULT_MAX_ARRAY_LENGTH;
					foreach (attr; attrs)
					{
						static if (is(typeof(attr) == MaxLenAttr))
							max_length = attr.max_length;
					}
					uint arr_length = *(cast(uint*) data.ptr);
					if (arr_length > max_length)
						throw new MaxLenExceeded(arr_length, max_length);
					local_shift += uint.sizeof;
					data = data[uint.sizeof .. $];
					// demarshal array
					enum element_size = ArrayElementSize!FieldType;
					FieldType arr = new ArrayElementType!(FieldType)[arr_length];
					pragma(msg, "FieldType = ", FieldType, " elementType = ", ArrayElementType!(FieldType));
					ubyte* field_ptr = cast(ubyte*) arr.ptr;
					uint byte_count = element_size * arr_length;
					for (uint i = 0; i < byte_count; i++, field_ptr++)
						*field_ptr = data[i];
					data = data[byte_count .. $];
					local_shift += byte_count;
					mixin("result." ~ field) = arr;
				}
				else
				{
					mixin("result." ~ field) = *(cast(FieldType*) data.ptr);
					enum field_size = mixin("(result." ~ field ~ ").sizeof");
					local_shift += field_size;
					data = data[field_size .. $];
					pragma(msg, field, " size is ", field_size);
				}
			}
		}
		shift = local_shift;
		return result;
	}
}
