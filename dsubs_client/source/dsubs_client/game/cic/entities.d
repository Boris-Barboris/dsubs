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
	double targetDir;	/// world-space direction from origin to target
}

struct PositionData
{
	vec2d targetPos;	/// world-space target position
}

struct SpeedData
{
	double speed;		/// absolute value of speed
}

union TargetDataUnion
{
	RayData ray;
	PositionData position;
	SpeedData speed;
}

/// Sensor data point that is related to one target
struct TargetData
{
	usecs_t time;
	DataType type;
	TargetDataUnion data;
	alias data this;
}

/// Most generic target type classification
enum TargetType: byte
{
	Unknown,
	Environment,
	Submarine,
	Weapon
}

/// Unique tracked target.
struct Target
{
	char prefix;
	int index;
	string comment;
	TargetType type;
	usecs_t createdAt;
}

/// Resulting kinematic snapshot of the solution.
struct SolutionKinematicSnap
{
	usecs_t time;
	vec2d pos;
	vec2d vel;
}