// Binary protocol messages

module dsubs_common.api.messages;

import dsubs_common.api.constants;
import dsubs_common.api.entities;
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
Authorization is done only once for TCP connection. */
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
	@MaxLenAttr(32) immutable(ubyte)[] dbHash;	/// entity database hash (SHA256)
}

/// Sent by server when it can offer an explanation on why the connection is
/// being closed.
struct SessionClosedRes
{
	__gshared const int g_marshIdx;
	@MaxLenAttr(64) string reason;
}

struct ClientPing
{
	__gshared const int g_marshIdx;
	usecs_t clientTime;
}

/// Sent in response to ClientPing
struct ServerPong
{
	__gshared const int g_marshIdx;
	usecs_t clientTime;		/// clientTime of the offending ClientPing
	usecs_t serverTime;
}

/// Sent by client when he wants to download entity database
struct EntityDbReq
{
	__gshared const int g_marshIdx;
}

/// Entity database, available to the client
struct EntityDbRes
{
	__gshared const int g_marshIdx;
	PropulsorTemplate[] propulsors;
	SubmarineTemplate[] controllableSubs;
	WeaponTemplate[] munition;
}