// Common functionality to serialize API messages into byte stream.
//
// Dsubs api is organized in units - structs that represent requests
// and responses.

module dsubs_common.api.streamer;

import std.meta;

public import dsubs_common.api.marshallers;
public import dsubs_common.math.hash;

/// Prototype of unit handler
alias UnitHandler = void delegate(void* unit_ptr);

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
	auto shift = marshal!ServerStatusResponse(&sr1, stream);
	auto mstream = stream[shift .. $];
	shift = marshal!ServerStatusRequest(&srq1, mstream);
	mstream = mstream[shift .. $];
	shift = marshal!ServerStatusResponse(&sr1, mstream);
	mstream = mstream[shift .. $];
	marshal!ServerStatusResponse(&sr1, mstream);
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
