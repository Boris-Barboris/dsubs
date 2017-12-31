module dsubs_common.api.marshalling;

import std.traits;
import std.meta;

import dsubs_common.api.messages;
import dsubs_common.api.utils;
import dsubs_common.meta;


alias MsgMarshallerT = byte[] function(const void* inMsgPtr);
alias MsgDemarshallerT = void function(void* outMsgPtr, const byte[] data);

// Static arrays of generated marshalling functions
immutable MsgMarshallerT[] g_msgMarshallers;
immutable MsgDemarshallerT[] g_msgDemarshallers;

static this()
{
	int idx = 0;
	foreach (member; Erase!("object", 
		Erase!("dsubs_common", __traits(allMembers, dsubs_common.api.messages))))
	{
		mixin("alias symbol = dsubs_common.api.messages." ~ member ~ ";");
		static if (is(symbol == struct))
		{
			pragma(msg, "Detected protocol message ", symbol);
			g_msgMarshallers ~= &marshalMessage!symbol;
			g_msgDemarshallers ~= &demarshalMessage!symbol;
			symbol.g_marshIdx = idx++;
		}
	}
}

void demarshalMessage(MsgT)(void* outMsgPtr, const byte[] data)
{
}

byte[] marshalMessage(MsgT)(const void* msg)
	if (is(MsgT == struct))
{
	return new byte[3];
}