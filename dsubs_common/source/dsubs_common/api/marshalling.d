module dsubs_common.api.marshalling;

import std.conv: to;
import std.exception: enforce;
import std.traits;
import std.meta;
import std.utf: validate;
import std.math: isNaN, isInfinity;

import dsubs_common.api.utils;
import dsubs_common.meta;


version (BigEndian)
{
	static assert (0, "marshalling code does not work on big-endian machines");
}

alias MsgMarshallerFunc = immutable(ubyte)[] function(immutable(void)* inMsgPtr);
alias MsgDemarshallerFunc = void function(void* outMsgPtr, const(ubyte)[] data);

void demarshalMessage(MsgT)(MsgT* outMsgPtr, const(ubyte)[] data)
	if (is(MsgT == struct))
{
	demarshalStruct(*outMsgPtr, data);
	enforce!ProtocolException(data.length == 0, "Leftover data after demarshalling");
}

immutable(ubyte)[] marshalMessage(MsgT)(immutable(MsgT)* msg)
	if (is(MsgT == struct))
{
	assert(msg);
	// 4 bytes on message type, 4 on message size. Then recursively descend into the
	// structure type and get the size of the byte buffer
	int byteCount = 0;
	getStructMarshLen!MsgT(*msg, byteCount);
	ubyte[] buf = new ubyte[byteCount + 8];
	*(cast(int*) &buf[0]) = MsgT.g_marshIdx;
	*(cast(int*) &buf[4]) = byteCount;
	ubyte[] volatileBuf = buf[8 .. $];
	marshalStruct!MsgT(*msg, volatileBuf);
	return cast(immutable(ubyte)[]) buf;
}


void getArrayMarshLen(ArrayT)(immutable ref ArrayT arr, ref int byteCount)
{
	static if (!isStaticArray!ArrayT)
		byteCount += 4;		// we write element count
	static if (isBasicType!(ArrayElementT!ArrayT))
	{
		byteCount += (arr.length * ArrayElementSize!ArrayT).to!int;
	}
	else static if (is(ArrayElementT!ArrayT == struct))
	{
		// array of structures
		foreach (el; arr)
			getStructMarshLen!(ArrayElementT!ArrayT)(el, byteCount);
	}
	else static if (isArray!(ArrayElementT!ArrayT))
	{
		// array of structures
		foreach (el; arr)
			getArrayMarshLen!(ArrayElementT!ArrayT)(el, byteCount);
	}
	else
		static assert(0, "Unable to marshal " ~ ArrayT.stringof);
}

void getStructMarshLen(StructT)(immutable ref StructT ptr, ref int byteCount)
{
	foreach (field; FieldNames!StructT)
	{
		alias MemberT = TypeOfMember!(StructT, field);
		static if (isBasicType!MemberT ||
			(is(MemberT == union) && !hasIndirections!MemberT))
		{
			byteCount += MemberT.sizeof;
		}
		else static if (isArray!MemberT)
		{
			static if (!isStaticArray!MemberT && HasUda!(StructT, field, MaxLenAttr))
			{
				// validate length of sender side
				int maxLen = GetUda!(StructT, field, MaxLenAttr).maxLength;
				int actualLength = __traits(getMember, ptr, field).length.to!int;
				if (actualLength > maxLen)
					throw new MaxLenExceeded(actualLength, maxLen);
			}
			getArrayMarshLen!MemberT(__traits(getMember, ptr, field), byteCount);
		}
		else static if (is(MemberT == struct))
			getStructMarshLen!(MemberT)(__traits(getMember, ptr, field), byteCount);
		else
			static assert(0, "Unable to marshal " ~ MemberT.stringof);
	}
}

void marshalArray(ArrayT)(immutable ref ArrayT arr, ref ubyte[] outBuf)
{
	static if (!isStaticArray!ArrayT)
	{
		*(cast(int*) outBuf.ptr) = arr.length.to!int;
		outBuf = outBuf[4 .. $];
	}
	static if (isBasicType!(ArrayElementT!ArrayT))
	{
		foreach (el; arr)
		{
			// Unqual because of immutable arrays (strings)
			*(cast(Unqual!(ArrayElementT!ArrayT) *) outBuf.ptr) = el;
			outBuf = outBuf[ArrayElementSize!ArrayT .. $];
		}
	}
	else static if (is(ArrayElementT!ArrayT == struct))
	{
		// array of structures
		foreach (el; arr)
			marshalStruct!(ArrayElementT!ArrayT)(el, outBuf);
	}
	else static if (isArray!(ArrayElementT!ArrayT))
	{
		// array of arrays
		foreach (el; arr)
			marshalArray!(ArrayElementT!ArrayT)(el, outBuf);
	}
	else
		static assert(0, "Unable to marshal " ~ ArrayT.stringof);
}

void marshalStruct(StructT)(immutable ref StructT ptr, ref ubyte[] outBuf)
{
	foreach (field; FieldNames!StructT)
	{
		alias MemberT = TypeOfMember!(StructT, field);
		static if (isBasicType!MemberT ||
			(is(MemberT == union) && !hasIndirections!MemberT))
		{
			*(cast(MemberT*) outBuf.ptr) = __traits(getMember, ptr, field);
			outBuf = outBuf[MemberT.sizeof .. $];
		}
		else static if (isArray!MemberT)
			marshalArray!(MemberT)(__traits(getMember, ptr, field), outBuf);
		else static if (is(MemberT == struct))
			marshalStruct!(MemberT)(__traits(getMember, ptr, field), outBuf);
		else
			static assert(0, "Unable to marshal " ~ MemberT.stringof);
	}
}

static assert (isStaticArray!(float[2]));


void demarshalArray(ArrayT)(ref ArrayT arr, ref const(ubyte)[] from, int maxLen = int.max)
{
	int arrLen = 0;
	static if (!isStaticArray!ArrayT)
	{
		enforce!ProtocolException(from.length >= 4);
		arrLen = *(cast(int*) from.ptr);
		from = from[4 .. $];
		if (arrLen < 0)
			throw new ProtocolException("Negative array length");
		if (arrLen > maxLen)
			throw new MaxLenExceeded(arrLen, maxLen);
		arr.reserve(arrLen);
	}
	else
		arrLen = arr.length.to!int;
	static if (isBasicType!(ArrayElementT!ArrayT))
	{
		enforce!ProtocolException(from.length >= ArrayElementSize!ArrayT * arrLen);
		for (int i = 0; i < arrLen; i++)
		{
			static if (!isStaticArray!ArrayT)
			{
				arr ~= *(cast(ArrayElementT!ArrayT *) from.ptr);
			}
			else
			{
				arr[i] = *(cast(ArrayElementT!ArrayT *) from.ptr);
			}
			static if (isFloatingPoint!(ArrayElementT!ArrayT))
			{
				if (isNaN(arr[i]))
					throw new ProtocolException("NaN poisoning");
				if (isInfinity(arr[i]))
					throw new ProtocolException("Infinity poisoning");
			}
			from = from[ArrayElementSize!ArrayT .. $];
		}
		static if (isSomeString!ArrayT)
		{
			validate(arr);
		}
	}
	else static if (is(ArrayElementT!ArrayT == struct))
	{
		for (int i = 0; i < arrLen; i++)
		{
			ArrayElementT!ArrayT newEl;
			demarshalStruct!(ArrayElementT!ArrayT)(newEl, from);
			static if (!isStaticArray!ArrayT)
				arr ~= newEl;
			else
				arr[i] = newEl;
		}
	}
	else static if (isArray!(ArrayElementT!ArrayT))
	{
		for (int i = 0; i < arrLen; i++)
		{
			ArrayElementT!ArrayT newEl;
			demarshalArray!(ArrayElementT!ArrayT)(newEl, from);
			static if (!isStaticArray!ArrayT)
				arr ~= newEl;
			else
				arr[i] = newEl;
		}
	}
	else
		static assert(0, "Unable to demarshal " ~ ArrayT.stringof);
}


void demarshalStruct(StructT)(ref StructT ptr, ref const(ubyte)[] from)
{
	foreach (field; FieldNames!StructT)
	{
		alias MemberT = TypeOfMember!(StructT, field);
		static if (isBasicType!MemberT ||
			(is(MemberT == union) && !hasIndirections!MemberT))
		{
			__traits(getMember, ptr, field) = *(cast(MemberT*) from.ptr);
			static if (isFloatingPoint!MemberT)
			{
				if (isNaN(__traits(getMember, ptr, field)))
					throw new ProtocolException("NaN poisoning");
				if (isInfinity(__traits(getMember, ptr, field)))
					throw new ProtocolException("Infinity poisoning");
			}
			enforce!ProtocolException(from.length >= MemberT.sizeof);
			from = from[MemberT.sizeof .. $];
		}
		else static if (isArray!MemberT)
		{
			int maxLen = int.max;
			static if (!isStaticArray!MemberT && HasUda!(StructT, field, MaxLenAttr))
				maxLen = GetUda!(StructT, field, MaxLenAttr).maxLength;
			demarshalArray!(MemberT)(__traits(getMember, ptr, field), from, maxLen);
		}
		else static if (is(MemberT == struct))
			demarshalStruct!(MemberT)(__traits(getMember, ptr, field), from);
		else
			static assert(0, "Unable to marshal " ~ MemberT.stringof);
	}
}

unittest
{
	struct TetsMsg
	{
		__gshared const int g_marshIdx = 3;
		@MaxLenAttr(64) string username;
		@MaxLenAttr(64) string password;
		string[] arrayOfStrings;
	}

	immutable TetsMsg req = TetsMsg("uname", "password", ["asdf", "foobar"]);
	immutable(ubyte)[] buf = marshalMessage(&req);
	TetsMsg res;
	demarshalMessage(&res, buf[8 .. $]);
	assert(res.username == req.username);
	assert(res.password == req.password);
	assert(res.arrayOfStrings == req.arrayOfStrings);
}