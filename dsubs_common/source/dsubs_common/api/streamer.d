// Common functionality to serialize API messages into byte stream.
//
// Dsubs api is organized in units - structs that represent requests
// and responses.

module dsubs_common.api.streamer;

import std.meta;

public import dsubs_common.api.auth;
public import dsubs_common.api.status;

import dsubs_common.api.utils;


public immutable string[] api_units = [
	"StatusRequest",
	"StatusResponse",
];

private mixin template UnitHandlers(string[] unit_names)
{
	mixin("void delegate(" ~ unit_names[$-1] ~ "*) " ~ unit_names[$-1] ~ "_handler;");
	static if (unit_names.length > 1)
		mixin UnitHandlers!(unit_names[0 .. $-1]);
}

// Generate code to fill dict with function pointers
private string UnitMarshallers(string[] unit_names, string dict_name,
							   string func_type, string func_name)()
{
	string result;
	foreach (unit_type; aliasSeqOf!unit_names)
	{
		result ~= dict_name ~ "[" ~ unit_type ~ ".header] = cast(" ~ func_type ~
				  ") &" ~ unit_type ~ "." ~ func_name ~ ";\n";
	}
	return result;
}

private alias Demarshaller = void* function(ubyte[] data, out uint shift);

immutable Demarshaller[header_t] demarshallers;

pragma(msg, "demarshallers:\n", UnitMarshallers!(api_units, "demarshallers",
								"Demarshaller", "demarshal"));

static this()
{
	mixin(UnitMarshallers!(api_units, "demarshallers", "Demarshaller", "demarshal"));
}

/// Prototype of unit handler
alias UnitHandler = void delegate(void* unit_ptr);

/// Class that handles byte stream parsing and
class APIStreamer
{
	UnitHandler[header_t] handlers;

	UnitHandler register_handler(UnitType)(void delegate(UnitType*) func)
	{
		auto key = UnitType.header;
		auto res = key in handlers;
		UnitHandler func_casted = cast(UnitHandler) func;
		handlers[key] = func_casted;
		if (res is null)
			return null;
		return *res;
	}

	/// Handle all units in byte stream
	void process(ubyte[] data)
	{
		while (data.length > HEADER_SIZE)
		{
			header_t header = data[0 .. HEADER_SIZE];
			if (header !in demarshallers)
				break;	// unknown header, abort processing
			Demarshaller func = demarshallers[header];
			uint shift;
			void* struct_ptr = func(data[HEADER_SIZE .. $], shift);
			// call handler
			if (header in handlers)
				handlers[header](struct_ptr);
			// now shift data pointer
			data = data[HEADER_SIZE + shift .. $];
		}
	}
}

unittest
{
	ubyte[] stream = new ubyte[64];
	StatusResponse sr1;
	StatusRequest srq1;
	sr1.status = ServerStatus.OFF;
	sr1.api_version = 1337;
	auto shift = sr1.marshal(stream);
	auto mstream = stream[shift .. $];
	shift = srq1.marshal(mstream);
	mstream = mstream[shift .. $];
	shift = sr1.marshal(mstream);
	mstream = mstream[shift .. $];
	sr1.marshal(mstream);
	uint called = 0;

	void handle_StatusResponse(StatusResponse* rsp)
	{
		assert(rsp.status == ServerStatus.OFF);
		assert(rsp.api_version == 1337);
		called++;
	}

	APIStreamer streamer = new APIStreamer;
	streamer.register_handler!(StatusResponse)(&handle_StatusResponse);
	streamer.process(stream);
	assert(called == 3);
}
