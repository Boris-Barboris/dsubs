// API for quering server state, version etc.

module dsubs_common.api.status;

import dsubs_common.api.utils;

/// Unit to send in order to get server status.
struct ServerStatusRequest
{
}

enum ServerStatus: ubyte
{
	OK = 0,
	OFF = 1
}

struct ServerStatusResponse
{
	ServerStatus status;
	uint api_version;
	uint players_online;
	@MaxLenAttr(512) string welcome_string;
}

/// Server sends this unit to the client when it drops the connection.
struct DisconnectSignal
{
	@MaxLenAttr(128) string reason;
}
