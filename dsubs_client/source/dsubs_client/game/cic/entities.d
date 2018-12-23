module dsubs_client.game.cic.entities;

import std.container.rbtree: RedBlackTree;

import dsubs_client.common;
import dsubs_common.api.utils;


/// Tag of a TargetData union
enum DataType: byte
{
	Ray,
	Position,
	Speed
}

struct RayData
{
	vec2d origin;		/// sensor position at the time
	double bearing;		/// world-space direction from origin to target
}

struct PositionData
{
	vec2d targetPos;	/// world-space target position
}

struct SpeedData
{
	double speed;		/// absolute speed value
}

union TargetDataUnion
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

/// Semantically target id consists of capital latin letter and a number.
struct TargetId
{
	char prefix;
	int postfix;
}

/// Sensor data point that is related to one target
struct TargetData
{
	int id = -1;		// globally-unique, monotonically increasing
	TargetId tgtId;
	usecs_t time;
	DataSource source;
	DataType type;
	TargetDataUnion data;
}

/// RB-tree of TargetData pointers, ordered by time.
alias TargetDataTree = RedBlackTree!(TargetData*,
	"a.time < b.time || (a.time == b.time && a.id < b.id)", false);

struct HydrophoneTracker
{
	int hydrophoneIdx;		/// index of a hydrophone
	TargetId tgtId;			/// periodically adds ray data to this target
	float bearing;			/// current world-space bearing
}

/// Most generic target type classification
enum TargetType: byte
{
	Unknown,
	Environment,
	Submarine,
	Weapon,
	Decoy
}

/// Unique tracked target.
struct Target
{
	TargetId id;		// unique
	@MaxLenAttr(128) string comment;
	TargetType type;
	usecs_t createdAt;
	TargetSolution solution;
}

/// Target kinematics
struct TargetSolution
{
	usecs_t time;
	/// Solution may lie on the last known ray (ray tracking mode), or have a concrete
	/// position (absolute position mode). The last mode is indicated by posAvailable = true.
	bool posAvailable;
	PositionData posData;
	/// Solution may or may not have velocity assigned.
	bool velAvailable;
	vec2d vel;
}