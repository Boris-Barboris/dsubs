module dsubs_client.game.cic.entities;

import dsubs_client.common;


/// Most generic target type classification
enum TargetType: int
{
	Unknown,
	Environment,
	Submarine,
	Weapon
}

/// Data point that contains sample of directional information about target.
struct RayData
{
	usecs_t time;
	vec2d origin;		/// sensor position at the time
	double targetDir;	/// world-space direction from origin to target
}

/// Data point that contains sample of raw target position.
struct PositionData
{
	usecs_t time;
	vec2d origin;		/// sensor position at the time
	vec2d targetPos;	/// world-space target position
}

/// Unique target.
struct TargetSolution
{
	string name;
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