/// CIC protocol messages
module dsubs_client.game.cic.messages;

public import dsubs_common.api.constants;
public import dsubs_common.api.entities;
public import dsubs_common.api.utils;


/// first message sent by client after connecting to CIC
struct CICLoginReq
{
	__gshared const int g_marshIdx;
	@MaxLenAttr(64) string password;
}

/// CIC server hello response that states the version
struct CICLoginRes
{
	__gshared const int g_marshIdx;
	@MaxLenAttr(32) immutable(ubyte)[] dbHash;	/// entity database hash (SHA256)
	int apiVersion = 1;
}

/// CIC client sends this to receive entity DB
struct CICEntityDbReq
{
	__gshared const int g_marshIdx;
}

/// CIC client sends this when he ensures that entity database is
/// OK and he is ready to participate in simulator message flow
struct CICEnterSimFlowReq
{
	__gshared const int g_marshIdx;
}

/*
Messages that duplicate backend protocol messages
*/

struct CICEntityDbRes
{
	__gshared const int g_marshIdx;
	PropulsorTemplate[] propulsors;
	SubmarineTemplate[] controllableSubs;
	WeaponTemplate[] munition;
}

struct CICReconnectStateRes
{
	__gshared const int g_marshIdx;
	int spawnId;
	@MaxLenAttr(64) string submarineName;
	@MaxLenAttr(64) string propulsorName;
	KinematicSnapshot subSnap;
	float targetCourse;
	float targetThrottle;
	float[] listenDirs;
}

struct CICSubKinematicRes
{
	__gshared const int g_marshIdx;
	KinematicSnapshot snap;
}

struct CICSubAcousticRes
{
	__gshared const int g_marshIdx;
	double rotationAtTime;
	AntennaeData[] data;
	HydrophoneAudio[] audio;
}

struct CICThrottleReq
{
	__gshared const int g_marshIdx;
	float target;
}

struct CICCourseReq
{
	__gshared const int g_marshIdx;
	float target;
}

struct CICListenDirReq
{
	__gshared const int g_marshIdx;
	int hydrophoneIdx;
	float dir;
}