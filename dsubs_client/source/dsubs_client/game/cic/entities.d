module dsubs_client.game.cic.entities;

import dsubs_client.common;


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

union SolutionDataUnion
{
	RayData ray;
	PositionData position;
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
	int sensorIdx;		/// index of a hydrophone/sonar if applicable
}

/// Sensor data point that is related to one target
struct TargetData
{
	int id;				// globally-unique, monotonically increasing
	usecs_t time;
	DataSource source;
	DataType type;
	TargetDataUnion data;
}

struct HydrophoneTracker
{
	int hydrophoneIdx;		/// index of a hydrophone
	string targetId;		/// periodically adds ray data to this target
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
	string id;		// unique
	string comment;
	TargetType type;
	usecs_t createdAt;
	TargetSolution solution;
}

/// Target kinematics
struct TargetSolution
{
	usecs_t time;
	/// Solution may lie on the ray (ray tracking mode), or have a concrete
	/// position (absolute position mode).
	DataType posType;
	SolutionDataUnion posData;
	/// Target may or may not have velocity calculated. If not, you should assume
	/// that target is stationary.
	bool velAvailable;
	vec2d vel;
}