module dsubs_common.api.marshalling;

import std.conv: to;
import std.traits;
import std.meta;

import dsubs_common.api.messages;
import dsubs_common.api.utils;
import dsubs_common.meta;


alias MsgMarshallerT = immutable(ubyte)[] function(immutable(void)* inMsgPtr);
alias MsgDemarshallerT = void function(void* outMsgPtr, const(ubyte)[] data);

// Static arrays of generated marshalling functions
__gshared immutable MsgMarshallerT[] g_msgMarshallers;
__gshared immutable MsgDemarshallerT[] g_msgDemarshallers;

shared static this()
{
	foreach (int idx, member; Erase!("object", Erase!("dsubs_common", 
		__traits(allMembers, dsubs_common.api.messages))))
	{
		mixin("alias symbol = dsubs_common.api.messages." ~ member ~ ";");
		static if (is(symbol == struct))
		{
			pragma(msg, "Detected protocol message ", symbol, ", assigning index ", idx);
			g_msgMarshallers ~= cast(MsgMarshallerT) &marshalMessage!symbol;
			g_msgDemarshallers ~= cast(MsgDemarshallerT) &demarshalMessage!symbol;
			*(cast(int*) &symbol.g_marshIdx) = idx;
		}
	}
}

void demarshalMessage(MsgT)(MsgT* outMsgPtr, const(ubyte)[] data)
{
	demarshalStruct(*outMsgPtr, data);
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
		static if (isBasicType!MemberT)
			byteCount += MemberT.sizeof;
		else static if (isArray!MemberT)
		{
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
		static if (isBasicType!MemberT)
		{
			*(cast(MemberT*) outBuf.ptr) = __traits(getMember, ptr, field);
			outBuf = outBuf[MemberT.sizeof .. $];
		}
		else static if (isArray!MemberT)
		{
			*(cast(int*) outBuf.ptr) = __traits(getMember, ptr, field).length.to!int;
			outBuf = outBuf[4 .. $];
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
					structSizeEstimation!(ArrayElementT!MemberT)(el, outBuf);
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

void demarshalStruct(StructT)(ref StructT ptr, ref const(ubyte)[] from)
{
	foreach (field; FieldNames!StructT)
	{
		alias MemberT = TypeOfMember!(StructT, field);
		static if (isBasicType!MemberT)
		{
			__traits(getMember, ptr, field) = *(cast(MemberT*) from.ptr);
			from = from[MemberT.sizeof .. $];
		}
		else static if (isArray!MemberT)
		{
			int arrLen = *(cast(int*) from.ptr);
			static if (HasUda!(StructT, field, MaxLenAttr))
			{
				// validate length
				int maxLen = GetUda!(StructT, field, MaxLenAttr).maxLength;
				if (arrLen > maxLen)
					throw new MaxLenExceeded(arrLen, maxLen);
			}
			__traits(getMember, ptr, field).reserve(arrLen);
			from = from[4 .. $];
			static if (isBasicType!(ArrayElementT!MemberT))
			{
				for (int i = 0; i < arrLen; i++)
				{
					__traits(getMember, ptr, field) ~= 
						*(cast(ArrayElementT!MemberT *) from.ptr);
					from = from[ArrayElementSize!MemberT .. $];
				}
			}
			else static if (is(ArrayElementT!MemberT == struct))
			{
				for (int i = 0; i < arrLen; i++)
				{
					ArrayElementT!MemberT newEl;
					demarshalStruct!(ArrayElementT!MemberT)(newEl, from);
					__traits(getMember, ptr, field) ~= newEl;
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
	immutable LoginReq req = LoginReq("uname", "password");
	ubyte[] buf = marshalMessage(&req);
	LoginReq res;
	demarshalMessage(&res, buf[8 .. $]);
	assert(res.username == req.username);
	assert(res.password == req.password);
}