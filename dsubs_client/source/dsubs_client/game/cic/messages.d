/// CIC protocol messages
module dsubs_client.game.cic.messages;

public import dsubs_common.api.constants;
public import dsubs_common.api.protocols.backend: ReconnectStateRes;
public import dsubs_common.api.entities;
public import dsubs_common.api.utils;

public import dsubs_client.game.cic.entities;


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
	ReconnectStateRes rawState;		/// raw reconnect state from backend
	Target[] targets;
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

struct CICSubSonarRes
{
	__gshared const int g_marshIdx;
	SonarSliceData[] data;
}

struct CICEmitPingReq
{
	__gshared const int g_marshIdx;
	int sonarIdx;
	float ilevel;
}


/*
Target and sensor data management API.
*/

/// Sent by client to create new target from initial data piece.
struct CICCreateTargetFromDataReq
{
	__gshared const int g_marshIdx;
	char tgtIdPrefix;		/// CIC will allocate new id for the target, wich will start with this letter
	TargetData initialData;	/// first data sample. Id and tgtId are ignored.
}

/// Broadcasted by CIC server when the new target is created.
struct CICTargetCreatedRes
{
	__gshared const int g_marshIdx;
	Target newTarget;
	TargetData initialData;
}

/// Request/broadcast to update target properties (type, comment, solution).
struct CICTargetUpdateReq
{
	__gshared const int g_marshIdx;
	Target target;
}

/// Sent by client to update or append new data sample to target.
/// Broadcasted by server when new data is produced by hydrophone tracker, or
/// one of the clients has sent this message.
struct CICTargetDataReq
{
	__gshared const int g_marshIdx;
	/// data.id should be set to -1 on client for the new data sample to be created.
	/// If id >= 0, it tries to update the data sample with the same id. TargetData can
	/// be reassigned from one target to another using this method.
	TargetData data;
}

/// Request/broadcast to drop target (drops related data).
struct CICDropTargetReq
{
	__gshared const int g_marshIdx;
	TargetId tgtId;
}

/// Request/broadcast to drop target data.
struct CICDropDataReq
{
	__gshared const int g_marshIdx;
	int dataId;
}

/// Request/broadcast to merge source target into dest target.
struct CICTargetMergeReq
{
	__gshared const int g_marshIdx;
	TargetId sourceTgtId;
	TargetId destTgtId;
}

/// Server broadcast the fact that it has deleted old TargetData.
struct CICDataRetentionRes
{
	__gshared const int g_marshIdx;
	usecs_t olderThan;
}