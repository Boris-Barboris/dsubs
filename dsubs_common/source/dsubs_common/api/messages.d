// Authorization API

module dsubs_common.api.messages;

import dsubs_common.api.constants;
import dsubs_common.api.utils;


// WARNING: all structs in this module are automatically registeded as
// complete protocol messages. Move all utility struct declarations to
// other modules.

/// Sent by client to check server status when opening main menu
struct ServerStatusReq
{
	__gshared const int g_marshIdx;
}

struct ServerStatusRes
{
	__gshared const int g_marshIdx;
	int apiVersion;
	int playersOnline;
}

/** This unit requests authorization from the server.
After authorization succeeded, you don't need to send any more of those.
Authorization is done once for TCP connection. */
struct LoginReq
{
	__gshared const int g_marshIdx;
	@MaxLenAttr(64) string username;
	@MaxLenAttr(64) string password;
}

struct LoginRes
{
	__gshared const int g_marshIdx;
	bool success;
	string welcomeMsg;	/// auth failure reason can be here
}

/// Sent by server when it can offer an explanation on connection being closed
struct SessionClosedRes
{
	__gshared const int g_marshIdx;
	@MaxLenAttr(64) string reason;
}