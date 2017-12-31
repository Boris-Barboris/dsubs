module dsubs_common.api.marshalling;

import std.traits;
import std.meta;

import dsubs_common.api.messages;
import dsubs_common.api.utils;
import dsubs_common.meta;


alias MsgMarshallerT = byte[] function(const void* inMsgPtr);
alias MsgDemarshallerT = void function(void* outMsgPtr, const byte[] data);

// Static arrays of generated marshalling functions
__gshared immutable MsgMarshallerT[] g_msgMarshallers;
__gshared immutable MsgDemarshallerT[] g_msgDemarshallers;

shared static this()
{
	int idx = 0;
	foreach (member; Erase!("object", Erase!("dsubs_common", 
		__traits(allMembers, dsubs_common.api.messages))))
	{
		mixin("alias symbol = dsubs_common.api.messages." ~ member ~ ";");
		static if (is(symbol == struct))
		{
			pragma(msg, "Detected protocol message ", symbol);
			g_msgMarshallers ~= cast(MsgMarshallerT) &marshalMessage!symbol;
			g_msgDemarshallers ~= cast(MsgDemarshallerT) &demarshalMessage!symbol;
			symbol.g_marshIdx = idx++;
		}
	}
}

void demarshalMessage(MsgT)(MsgT* outMsgPtr, const byte[] data)
{
}

byte[] marshalMessage(MsgT)(const MsgT* msg)
	if (is(MsgT == struct))
{
	assert(msg);
	// 4 bytes on message type, 4 on message size. Then recursively descend into the 
	// structure type and get the size of the byte buffer
	int byteCount = 8;	
	structSizeEstimation!MsgT(*outMsgPtr, byteCount);
	byte[] buf = new byte[byteCount];
	*(cast(int*) &buf[0]) = MsgT.g_marshIdx;
	*(cast(int*) &buf[4]) = byteCount;
	structMarshalling(*outMsgPtr, buf[8..$]);
	return buf;
}

private:

void structSizeEstimation(StructT)(ref StructT ptr, ref int byteCount)
{
	foreach (field; __traits(allMembers, StructT))
	{
		alias MemberT = TypeOfMember!(StructT, field);
		static if (isBasicType!MemberT)
			byteCount += MemberT.sizeof;
		else static if (isArray!MemberT)
		{
			byteCount += 4;		// we write element count
			static if (isBasicType!(ArrayElementT!MemberT))
				byteCount += __traits(getMember, ptr, field).length * 
					ArrayElementSize!MemberT;
			else static if (is(ArrayElementT!MemberT == struct))
			{
				// array of structures
				foreach (el; __traits(getMember, ptr, field))
					structSizeEstimation!(ArrayElementT!MemberT)(el, byteCount);
			}
			else
				static assert(0, "Unable to marshal " ~ MemberT.stringof);
		}
		else static if (is(MemberT == struct))
		{
			structSizeEstimation!(MemberT)(__traits(getMember, ptr, field), byteCount);
		}
		else
			static assert(0, "Unable to marshal " ~ MemberT.stringof);
	}
}

void structMarshalling(StructT)(ref StructT ptr, byte[] outBuf)
{
	foreach (field; __traits(allMembers, StructT))
	{
		alias MemberT = TypeOfMember!(StructT, field);
		static if (isBasicType!MemberT)
		{
			*outBuf.ptr = __traits(getMember, ptr, field);
			outBuf = outBuf[MemberT.sizeof .. $];
		}
		else static if (isArray!MemberT)
		{
			*outBuf.ptr = cast(int) __traits(getMember, ptr, field).length;
			outBuf = outBuf[4 .. $];
			static if (isBasicType!(ArrayElementT!MemberT))
			{
				foreach (el; __traits(getMember, ptr, field))
				{
					*outBuf.ptr = el;
					import std.outbuffer;
					OutBuffer buf = new OutBuffer();
				}
			}
			else static if (is(ArrayElementT!MemberT == struct))
			{
				// array of structures
				foreach (el; __traits(getMember, ptr, field))
					structSizeEstimation!(ArrayElementT!MemberT)(el, byteCount);
			}
			else
				static assert(0, "Unable to marshal " ~ MemberT.stringof);
		}
		else static if (is(MemberT == struct))
		{
			structSizeEstimation!(MemberT)(__traits(getMember, ptr, field), byteCount);
		}
		else
			static assert(0, "Unable to marshal " ~ MemberT.stringof);
	}
}