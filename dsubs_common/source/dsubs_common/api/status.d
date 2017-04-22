// API for quering server state, version etc.

module dsubs_common.api.status;

import dsubs_common.api.utils;
public import dsubs_common.mutstring;


/// Unit to send in order to get server status.
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
	uint players_online;
	@MaxLenAttr(128) mutstring welcome_string;
}

/// Server sends this unit to the client when it drops the connection.
struct DisconnectSignal
{
	static header_t header = cast(header_t) "signdrop";
	@MaxLenAttr(128) mutstring reason;
}
