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
	int apiVersion = 6;
}

/** This message requests authorization from the server.
After authorization succeeded, you must not send any more of those.
Authorization is done only once for TCP connection. */
struct LoginReq
{
	__gshared const int g_marshIdx;
	@MaxLenAttr(1024) ubyte[] username;		/// maybe encrypted
	@MaxLenAttr(1024) ubyte[] password;		/// maybe encrypted
}

struct LoginRes
{
	__gshared const int g_marshIdx;
	bool success;
	string welcomeMsg;	/// auth failure reason can be here
	@MaxLenAttr(32) immutable(ubyte)[] dbHash;	/// entity database hash (SHA256)
	/// true when the player already has a submarine to reconnect to.
	bool alreadySpawned;
	/// if spawn was rejected because the player has died recently, this will
	/// be the time in seconds left until the spawn is allowed again.
	int secsLeft;
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
	WeaponTemplate[] weapons;
}

/// request to spawn with chosen loadout
struct SpawnReq
{
	__gshared const int g_marshIdx;
	@MaxLenAttr(64) string submarineName;
	@MaxLenAttr(64) string propulsorName;
	@MaxLenAttr(16) AmmoRoomFullState[] ammoRoomLoadouts;
	/// Only the tubes with 'loadedOnSpawn'=true must be specified here.
	@MaxLenAttr(16) TubeSpawnState[] loadableTubeLoadouts;
}

/// If spawn was allowed (spawnAllowed == true), this message will be followed by
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
/// instead of SpawnReq when 'alreadySpawned' from LoginRes was true.
/// Server will reply with ReconnectStateRes and resume normal
/// simulator flow message streaming.
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
	WireSnapshot[] wireSnaps;
	float targetCourse;
	float targetThrottle;
	float[] listenDirs;
	TubeFullState[] tubeStates;
	AmmoRoomFullState[] ammoRoomStates;
	MapElement[] mapElements;
	ChatMessage briefing;
}

/*
SIMULATOR FLOW MESSAGES:

following messages are sent and received when client and backend both enter
normal simulation state by either successfully spawning submarine or
reconnecting to it.
*/

/// Server periodically sends the player updates with his submarine position.
struct SubKinematicRes
{
	__gshared const int g_marshIdx;
	KinematicSnapshot snap;
	// all the wires that are attached to the sub are reported.
	WireSnapshot[] wireSnaps;
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

/// Sent by client in order to specify listening direction for a hydrophone
struct ListenDirReq
{
	__gshared const int g_marshIdx;
	int hydrophoneIdx;
	float dir;		/// world-space listen direction
}

/// Server streams acoustic data to the player. All hydrophones that were active
/// are represented here. If some hydrophone is absent, it was inactive.
struct AcousticStreamRes
{
	__gshared const int g_marshIdx;
	usecs_t atTime;
	HydrophoneData[] data;
	HydrophoneAudio[] audio;
}

/// Active sonar data is stream to the player as well
struct SonarStreamRes
{
	__gshared const int g_marshIdx;
	usecs_t atTime;
	SonarSliceData[] data;
}

/// Client sends when he wants to emit a ping via active sonar.
/// Server may ignore this request for optimization purposes (cooldown)
struct EmitPingReq
{
	__gshared const int g_marshIdx;
	int sonarIdx;
	float ilevel;	/// intensity level
}

/// Server sends when the player dies.
struct DeathRes
{
	__gshared const int g_marshIdx;
	string cause;
	string longReport;
}

/// Client requests to change desired loaded weapon.
/// If the tube is in incorrect state, message is ignored.
/// To unload the weapon from the tube completely, set
/// 'weaponName' to empty string.
struct LoadTubeReq
{
	__gshared const int g_marshIdx;
	int tubeId;
	string weaponName;
}

/// Client requests to change the desired tube state. Only the correct
/// state machine evolutions are accepted, otherwise the message
/// is ignored.
struct SetTubeStateReq
{
	__gshared const int g_marshIdx;
	int tubeId;
	/// Server will walk through the state machine until the tube reaches
	/// desired state. Only one of 3 stable states can be specified here.
	TubeState desiredState;
}

/// Client requests to launch the weapon in the tube.
/// Weapon parameters MUST be correct.
struct LaunchTubeReq
{
	__gshared const int g_marshIdx;
	int tubeId;
	/// If this weapon does not match the actual loaded weapon,
	/// the request is ignored. Prevents race conditions.
	string weaponName;
	@MaxLenAttr(32) WeaponParamValue[] weaponParams;
}

/// Server reports tube state change.
struct TubeStateUpdateRes
{
	__gshared const int g_marshIdx;
	TubeFullState tube;
}

/// Server reports ammo room state change.
struct AmmoRoomStateUpdateRes
{
	__gshared const int g_marshIdx;
	AmmoRoomFullState room;
}

/// Map overlay state is always updated as a whole.
struct MapOverlayUpdateRes
{
	__gshared const int g_marshIdx;
	MapElement[] mapElements;
}

/// Backend sends a message to client.
struct ChatMessageRes
{
	__gshared const int g_marshIdx;
	ChatMessage message;
}