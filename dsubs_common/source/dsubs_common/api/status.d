// API for quering server state, version etc.

module dsubs_common.api.status;

import dsubs_common.api.utils;


struct StatusRequest
{
	static header_t header = cast(header_t) "statureq";

	mixin DefaultDemarshaller!StatusRequest;
	mixin DefaultMarshaller!StatusRequest;
}

enum ServerStatus: ubyte
{
	OK = 0,
	OFF = 1
}

struct StatusResponse
{
	static header_t header = cast(header_t) "statures";
	ServerStatus status;
	uint api_version;

	mixin DefaultDemarshaller!StatusResponse;
	mixin DefaultMarshaller!StatusResponse;
}
