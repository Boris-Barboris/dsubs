// Common functionality to serialize API messages into byte stream.
//
// Dsubs api is organized in units - structs that represent requests
// and responses.

module dsubs_common.api.streamer;

import std.conv;
import std.meta;

public import dsubs_common.api.marshallers;
public import dsubs_common.math.hash;

/// Prototype of unit handler
alias UnitHandler = void delegate(void* unit_ptr);

class UnknownUnit: Exception
{
	header_t header;
	this(header_t header)
	{
		super("Unknown unit header " ~ to!string(header));
		this.header = header;
	}
}

/// Class that handles byte stream demarshalling
class APIStreamer
{
	UnitHandler[header_t] handlers;

	/// Set handler to call when unit is found in the byte stream
	UnitHandler set_handler(UnitType)(void delegate(UnitType*) func)
	{
		enum key = djb2(UnitType.stringof);
		UnitHandler* res = key in handlers;
		UnitHandler old_handler = res ? *res : null;
		UnitHandler func_casted = cast(UnitHandler) func;
		handlers[key] = func_casted;
		return old_handler;
	}

	/// Handle all units in byte stream
	void process(ubyte[] data)
	{
		while (data.length > HEADER_SIZE)
		{
			header_t header = *(cast(header_t*) data.ptr);
			if (header !in demarshallers)
				throw new UnknownUnit(header);
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

import dsubs_common.api.status;

unittest
{
	ubyte[] stream = new ubyte[256];
	ServerStatusResponse sr1;
	ServerStatusRequest srq1;
	sr1.status = ServerStatus.OFF;
	sr1.api_version = 1337;
	string welcome_string = "TestString";
	sr1.welcome_string = welcome_string;
	uint global_shift = 0;
	auto shift = marshal!ServerStatusResponse(&sr1, stream);
	auto mstream = stream[shift .. $];
	global_shift += shift;
	shift = marshal!ServerStatusRequest(&srq1, mstream);
	global_shift += shift;
	mstream = mstream[shift .. $];
	shift = marshal!ServerStatusResponse(&sr1, mstream);
	global_shift += shift;
	mstream = mstream[shift .. $];
	global_shift += marshal!ServerStatusResponse(&sr1, mstream);
	stream = stream[0 .. global_shift];

	uint called = 0;

	void handle_StatusResponse(ServerStatusResponse* rsp)
	{
		assert(rsp.status == ServerStatus.OFF);
		assert(rsp.api_version == 1337);
		assert(rsp.welcome_string == welcome_string);
		called++;
	}

	APIStreamer streamer = new APIStreamer;
	streamer.set_handler!(ServerStatusResponse)(&handle_StatusResponse);
	streamer.process(stream);
	assert(called == 3);
}
