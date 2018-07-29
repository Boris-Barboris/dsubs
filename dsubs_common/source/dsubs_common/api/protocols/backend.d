/// Protocol messages for master-client - dsubs backend interactions.

module dsubs_common.api.protocols.backend;

public import dsubs_common.api.constants;
public import dsubs_common.api.entities;
public import dsubs_common.api.utils;


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
	int playersOnline;
	int apiVersion = 1;
}

/** This message requests authorization from the server.
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

	/// true when the player already has a submarine to reconnect to.
	bool alreadySpawned;
}

/// Sent by server when it can offer an explanation on why the connection is
/// being closed.
struct SessionClosedRes
{
	__gshared const int g_marshIdx;
	@MaxLenAttr(64) string reason;
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

/// request to spawn with chosen loadout
struct SpawnReq
{
	__gshared const int g_marshIdx;
	@MaxLenAttr(64) string submarineName;
	@MaxLenAttr(64) string propulsorName;
}

/// If swapw was allowed, this message will be followed by
/// ReconnectStateRes.
struct SpawnRes
{
	__gshared const int g_marshIdx;

	/// true when the server has accepted your spawn request
	bool spawnAllowed;

	/// if spawn was rejected because the player has died recently, this will
	/// be the time in seconds left until the spawn is allowed again.
	int secsLeft;
}

/// request to reconnect to existing submarine. Should be issued
/// when 'alreadySpawned' from LoginRes was true instead of SpawnReq.
/// Server will reply with ReconnectStateRes and resume normal
/// streaming flow operations.
struct ReconnectReq
{
	__gshared const int g_marshIdx;
}

/// Right after successfull spawn or reconnection server flushes the submarine
/// configuration and state to the client using this message.
struct ReconnectStateRes
{
	__gshared const int g_marshIdx;
	int spawnId;
	@MaxLenAttr(64) string submarineName;
	@MaxLenAttr(64) string propulsorName;
	KinematicSnapshot subSnap;
	float targetCourse;
	float targetThrottle;
}

/*
SIMULATOR FLOW MESSAGES:

following messages are sent and received when client and backend both enter
normal simulation state by either successfully spawning submarine or
reconnecting to it.
*/

/// Server periodically sends the player updates with his submarine position
struct SubKinematicRes
{
	__gshared const int g_marshIdx;
	KinematicSnapshot snap;
}

/// Sent by client in order to update desired throttle on his submarine
struct ThrottleReq
{
	__gshared const int g_marshIdx;
	float target;
}

/// Sent by client in order to update desired course of his submarine
struct CourseReq
{
	__gshared const int g_marshIdx;
	float target;
}

/// Server streams acoustic data to the player
struct AcousticStreamRes
{
	__gshared const int g_marshIdx;
	usecs_t atTime;
	AntennaeData[] cells;
}