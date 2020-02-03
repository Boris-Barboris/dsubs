module dsubs_common.api.protocol;

import std.string: split;
import std.meta: Erase;
import dsubs_common.api.marshalling;


/// Static storage for protocol message serialization\deserialization functions.
template Protocol(string messagesModule)
{
	mixin("import " ~ messagesModule ~ ";");
	mixin("alias msgModule = " ~ messagesModule ~ ";");
	// pragma(msg, "Generating protocol for module " ~ messagesModule);

	static
	{
		immutable MsgMarshallerFunc[] msgMarshallers;
		immutable MsgDemarshallerFunc[] msgDemarshallers;
		immutable string[] msgTypeNames;
		immutable int msgTypeCount;
	}

	// Generate marsh\demarsh functions for structures in dsubs_common.api.messages
	shared static this()
	{
		// allMembers for module returns all declarations in it and two
		// service literals - "object" and name of the package wich is
		// the same as first word in full module path.
		enum string packageName = messagesModule.split(".")[0];
		int idx = 0;
		foreach (member; Erase!("object", Erase!(packageName,
			__traits(allMembers, msgModule))))
		{
			mixin("alias symbol = " ~ messagesModule ~ "." ~ member ~ ";");
			static if (is(symbol == struct))
			{
				// pragma(msg, "Detected protocol message ", symbol);
				msgMarshallers ~= cast(MsgMarshallerFunc) &marshalMessage!symbol;
				msgDemarshallers ~= cast(MsgDemarshallerFunc) &demarshalMessage!symbol;
				msgTypeNames ~= symbol.stringof;
				// next we assign a number to this message type
				*(cast(int*) &symbol.g_marshIdx) = idx++;
				msgTypeCount++;
			}
		}
	}

	static immutable(ubyte)[] marshal(MsgT)(immutable MsgT msg)
		if (is(MsgT == struct))
	{
		mixin("alias known = " ~ messagesModule ~ "." ~ MsgT.stringof ~ ";");
		static assert (is(known == MsgT), "message type " ~ MsgT.stringof ~
			" not found in protocol");
		return msgMarshallers[MsgT.g_marshIdx](&msg);
	}

	static MsgT demarshal(MsgT)(const(ubyte)[] rawData)
		if (is(MsgT == struct))
	{
		mixin("alias known = " ~ messagesModule ~ "." ~ MsgT.stringof ~ ";");
		static assert (is(known == MsgT), "message type " ~ MsgT.stringof ~
			" not found in protocol");
		MsgT result;
		msgDemarshallers[MsgT.g_marshIdx](&result, rawData);
		return result;
	}
}

/// Protocol for client-backend interactions
alias BackendProtocol = Protocol!"dsubs_common.api.messages";


unittest
{
	assert(BackendProtocol.msgTypeCount > 0);
	alias ServerStatusRes = dsubs_common.api.messages.ServerStatusRes;
	immutable ServerStatusRes testStruct;
	auto bytes = BackendProtocol.marshal(testStruct);
	assert(bytes.length > 0);

	// named as actual Protocol message, but it should be rejected in compile-time
	struct EntityDbRes
	{
		__gshared int g_marshIdx = 13;
	}
	static assert (__traits(compiles, BackendProtocol.marshal(immutable ServerStatusRes())));
	static assert (!__traits(compiles, BackendProtocol.marshal(immutable EntityDbRes())));
}