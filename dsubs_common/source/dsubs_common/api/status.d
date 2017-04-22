// API for quering server state, version etc.

module dsubs_common.api.status;

import dsubs_common.api.utils;
import dsubs_common.mutstring;


struct StatusRequest
{
	static header_t header = cast(header_t) "statureq";
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
	@MaxLenAttr(128) mutstring welcome_string;
}
