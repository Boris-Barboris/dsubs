module dsubs_client.game.cic.entities;

import std.container.rbtree: RedBlackTree;

import dsubs_client.common;
import dsubs_common.api.utils;


/// Tag of a ContactData union
enum DataType: byte
{
	Ray,
	Position,
	Speed
}

struct RayData
{
	vec2d origin = vec2d(0, 0);		/// sensor position at the time
	double bearing = 0.0;			/// world-space direction from origin to contact
}

struct PositionData
{
	vec2d contactPos = vec2d(0, 0);	/// world-space contact position
}

struct SpeedData
{
	double speed = 0.0;		/// absolute speed value
}

union ContactDataUnion
{
	RayData ray;
	PositionData position;
	SpeedData speed;
}

enum DataSourceType: byte
{
	Manual,
	Hydrophone,
	ActiveSonar
}

struct DataSource
{
	DataSourceType type;
	int sensorIdx;		/// index of a hydrophone/sonar, if applicable
}

/// Semantically contact id consists of capital latin letter and a number.
struct ContactId
{
	char prefix;
	int postfix;

	void toString(scope void delegate(const(char)[]) sink) const
	{
		import std.format: formattedWrite;
		sink.formattedWrite!"%c"(prefix);
		sink.formattedWrite!"%d"(postfix);
	}
}

/// Sensor data point that is related to one contact
struct ContactData
{
	int id = -1;		// globally-unique, monotonically increasing
	ContactId ctcId;
	usecs_t time;
	DataSource source;
	DataType type;
	ContactDataUnion data;
}

/// RB-tree of ContactData pointers, ordered by time.
alias ContactDataTree = RedBlackTree!(ContactData*,
	"a.time < b.time || (a.time == b.time && a.id < b.id)", false);

struct HydrophoneTracker
{
	int hydrophoneIdx;		/// index of a hydrophone
	ContactId ctcId;		/// periodically adds ray data to this contact
	float bearing = 0.0f;	/// current world-space bearing
}

/// Most generic contact type classification
enum ContactType: byte
{
	Unknown,
	Environment,
	Submarine,
	Weapon,
	Decoy
}

/// Unique tracked contact.
struct Contact
{
	ContactId id;		// unique
	@MaxLenAttr(128) string comment;
	ContactType type;
	usecs_t createdAt;
	ContactSolution solution;
}

/// Contact kinematics
struct ContactSolution
{
	usecs_t time;
	/// Solution may lie on the last known ray (ray tracking mode), or have a designated
	/// position (absolute position mode). The last mode is indicated by posAvailable = true.
	bool posAvailable;
	PositionData posData;
	/// Solution may or may not have velocity assigned.
	bool velAvailable;
	vec2d vel = vec2d(0, 0);
}