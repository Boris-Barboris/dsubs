module dsubs_common.api.marshalling;

import std.conv: to;
import std.exception: enforce;
import std.traits;
import std.meta;
import std.math: isNaN, isInfinity;

import dsubs_common.api.utils;
import dsubs_common.meta;


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



private:

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
			static if (!isStaticArray!MemberT)
				byteCount += 4;		// we write element count
			static if (HasUda!(StructT, field, MaxLenAttr))
			{
				// validate length
				int maxLen = GetUda!(StructT, field, MaxLenAttr).maxLength;
				int actualLength = __traits(getMember, ptr, field).length.to!int;
				if (actualLength > maxLen)
					throw new MaxLenExceeded(actualLength, maxLen);
			}
			static if (isBasicType!(ArrayElementT!MemberT))
				byteCount += (__traits(getMember, ptr, field).length *
					ArrayElementSize!MemberT).to!int;
			else static if (is(ArrayElementT!MemberT == struct))
			{
				// array of structures
				foreach (el; __traits(getMember, ptr, field))
					getStructMarshLen!(ArrayElementT!MemberT)(el, byteCount);
			}
			else
				static assert(0, "Unable to marshal " ~ MemberT.stringof);
		}
		else static if (is(MemberT == struct))
			getStructMarshLen!(MemberT)(__traits(getMember, ptr, field), byteCount);
		else
			static assert(0, "Unable to marshal " ~ MemberT.stringof);
	}
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
		{
			static if (!isStaticArray!MemberT)
			{
				*(cast(int*) outBuf.ptr) = __traits(getMember, ptr, field).length.to!int;
				outBuf = outBuf[4 .. $];
			}
			static if (isBasicType!(ArrayElementT!MemberT))
			{
				foreach (el; __traits(getMember, ptr, field))
				{
					// Unqual because of immutable arrays (strings)
					*(cast(Unqual!(ArrayElementT!MemberT) *) outBuf.ptr) = el;
					outBuf = outBuf[ArrayElementSize!MemberT .. $];
				}
			}
			else static if (is(ArrayElementT!MemberT == struct))
			{
				// array of structures
				foreach (el; __traits(getMember, ptr, field))
					marshalStruct!(ArrayElementT!MemberT)(el, outBuf);
			}
			else
				static assert(0, "Unable to marshal " ~ MemberT.stringof);
		}
		else static if (is(MemberT == struct))
			marshalStruct!(MemberT)(__traits(getMember, ptr, field), outBuf);
		else
			static assert(0, "Unable to marshal " ~ MemberT.stringof);
	}
}

static assert (isStaticArray!(float[2]));

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
			int arrLen = 0;
			static if (!isStaticArray!MemberT)
			{
				arrLen = *(cast(int*) from.ptr);
				enforce!ProtocolException(from.length >= 4);
				from = from[4 .. $];
				if (arrLen < 0)
					throw new ProtocolException("Negative array length");
				static if (HasUda!(StructT, field, MaxLenAttr))
				{
					int maxLen = GetUda!(StructT, field, MaxLenAttr).maxLength;
					if (arrLen > maxLen)
						throw new MaxLenExceeded(arrLen, maxLen);
				}
				__traits(getMember, ptr, field).reserve(arrLen);
			}
			else
				arrLen = __traits(getMember, ptr, field).length.to!int;
			static if (isBasicType!(ArrayElementT!MemberT))
			{
				enforce!ProtocolException(from.length >= ArrayElementSize!MemberT * arrLen);
				for (int i = 0; i < arrLen; i++)
				{
					static if (!isStaticArray!MemberT)
					{
						__traits(getMember, ptr, field) ~=
							*(cast(ArrayElementT!MemberT *) from.ptr);
					}
					else
					{
						__traits(getMember, ptr, field)[i] =
							*(cast(ArrayElementT!MemberT *) from.ptr);
					}
					static if (isFloatingPoint!(ArrayElementT!MemberT))
					{
						if (isNaN(__traits(getMember, ptr, field)[i]))
							throw new ProtocolException("NaN poisoning");
						if (isInfinity(__traits(getMember, ptr, field)[i]))
							throw new ProtocolException("Infinity poisoning");
					}
					from = from[ArrayElementSize!MemberT .. $];
				}
			}
			else static if (is(ArrayElementT!MemberT == struct))
			{
				for (int i = 0; i < arrLen; i++)
				{
					ArrayElementT!MemberT newEl;
					demarshalStruct!(ArrayElementT!MemberT)(newEl, from);
					static if (!isStaticArray!MemberT)
						__traits(getMember, ptr, field) ~= newEl;
					else
						__traits(getMember, ptr, field)[i] = newEl;
				}
			}
			else
				static assert(0, "Unable to demarshal " ~ MemberT.stringof);
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
	}

	immutable TetsMsg req = TetsMsg("uname", "password");
	immutable(ubyte)[] buf = marshalMessage(&req);
	TetsMsg res;
	demarshalMessage(&res, buf[8 .. $]);
	assert(res.username == req.username);
	assert(res.password == req.password);
}