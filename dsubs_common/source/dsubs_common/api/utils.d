module dsubs_common.api.utils;

import std.algorithm.comparison;
import std.meta;
import std.traits;

import dsubs_common.reflection;


immutable uint HEADER_SIZE = 8;
immutable uint DEFAULT_MAX_ARRAY_LENGTH = 1024;
alias header_t = immutable(ubyte[HEADER_SIZE]);

struct MaxLenAttr
{
	uint max_length;
	this(uint max_length) { this.max_length = max_length; }
}

class MaxLenExceeded: Exception
{
	this(string message) { super(message); }
}

template ArrayElementSize(T) if (isArray!T)
{
	enum ArrayElementSize = (ArrayElementType!T).sizeof;
}

template ArrayAwareMarshaller(T)
{
	uint marshal(const(T)* ptr, ubyte[] stream)
	{
		uint shift = HEADER_SIZE;
		for (uint i = 0; i < HEADER_SIZE; i++)
			stream[i] = T.header[i];
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
							max_length = min(max_length, attr.max_length);
					}
					// serialize array size
					FieldType arr = mixin("ptr." ~ field);
					uint length = arr.length;
					if (length > max_length)
						throw new MaxLenExceeded(
							"Exceeded max length of " ~ T.stringof ~ "." ~ field);
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
}

template ArrayAwareDemarshaller(T)
{
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
							max_length = min(max_length, attr.max_length);
					}
					uint arr_length = *(cast(uint*) data.ptr);
					if (arr_length > max_length)
						throw new MaxLenExceeded(
							"Exceeded max length of " ~ T.stringof ~ "." ~ field);
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
