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
	Contact[] contacts;
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
	HydrophoneData[] data;
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
Contact and sensor data management API.
*/

/// Sent by client to create new contact from initial data piece.
struct CICCreateContactFromDataReq
{
	__gshared const int g_marshIdx;
	char ctcIdPrefix;		/// CIC will allocate new id for the contact, wich will start with this letter
	ContactData initialData;	/// first data sample. Id and ctcId are ignored.
}

/// Broadcasted by CIC server when the new contact is created.
struct CICContactCreatedFromDataRes
{
	__gshared const int g_marshIdx;
	Contact newContact;
	ContactData initialData;
}

/// Sent by client to create new contact and a hydrophone tracker.
struct CICCreateContactFromHTrackerReq
{
	__gshared const int g_marshIdx;
	char ctcIdPrefix;
	int hydrophoneIdx;
	float bearing;
}

/// Broadcasted by CIC server when the new contact is created.
struct CICContactCreatedFromHTrackerRes
{
	__gshared const int g_marshIdx;
	Contact newContact;
	HydrophoneTracker tracker;
}

/// Request/broadcast to update contact properties (type, comment, solution).
/// Id and createdAt cannot be updated.
struct CICContactUpdateReq
{
	__gshared const int g_marshIdx;
	Contact contact;
}

/// Sent by client to update or append new data sample to contact.
/// Broadcasted by server when new data is produced by hydrophone tracker, or
/// one of the clients has sent this message and the update/create succeeded.
struct CICContactDataReq
{
	__gshared const int g_marshIdx;
	/// data.id should be set to -1 on client for the new data sample to be appended.
	/// If id >= 0, it tries to update the data sample with the same id. ContactData can
	/// be reassigned from one contact to another using this method. Contact source and
	/// type cannot be changed.
	ContactData data;
}

/// Request/broadcast to drop contact (drops all related data).
struct CICDropContactReq
{
	__gshared const int g_marshIdx;
	ContactId ctcId;
}

/// Request/broadcast to drop contact data.
struct CICDropDataReq
{
	__gshared const int g_marshIdx;
	int dataId;
}

/// Request/broadcast to merge source contact into dest contact.
struct CICContactMergeReq
{
	__gshared const int g_marshIdx;
	ContactId sourceCtcId;
	ContactId destCtcId;
}

/// Broadcasted by CIC when it finished analyzing new acoustic slice and contains all peaks and tracker states
/// for one hydrophone
struct CICWaterfallUpdateRes
{
	__gshared const int g_marshIdx;
	int hydrophoneIdx;
	float[] peaks;
	HydrophoneTracker[] trackers;
}

/// Sent by client and then broadcasted back to update tracker's bearing
struct CICUpdateTrackerReq
{
	__gshared const int g_marshIdx;
	HydrophoneTracker tracker;
}

/// Sent by client and then broadcasted back to drop a tracker
struct CICDropTrackerReq
{
	__gshared const int g_marshIdx;
	TrackerId tid;
}