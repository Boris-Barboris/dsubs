module dsubs_common.api.entities;

import std.traits;

import gfm.math.vector;

import dsubs_common.api.constants;
import dsubs_common.api.utils;


struct RgbaColor
{
	ubyte r, g, b;
	ubyte a = 255;
}

struct ConvexPolygon
{
	vec2f[] points;	/// counter-clockwise vertices
	RgbaColor fillColor;
	float borderWidth = 0.0f;
	RgbaColor borderColor;
}

enum PropulsorType: ubyte
{
	SCREW,
	PUMP
}

struct PropulsorTemplate
{
	/// human-readable name
	string name;

	/// description of this propulsor
	string description;

	PropulsorType type;

	/// if type is SCREW, this is the number of blades.
	ubyte bladeCount;

	/// 1 screw blade for screws, whole pump for pumps
	ConvexPolygon model;
}

struct MountPoint
{
	vec2f mountCenter;
	float rotation = 0.0f;
	float scale = 1.0f;
}

/// Playable submarine template
struct SubmarineTemplate
{
	/// human-readable name
	string name;

	/// description to present to the player on prepare screen
	string description;

	/// main hull model. First element is the deepest (drawn first) one.
	ConvexPolygon[] hullModel;

	/// mount points for screws.
	MountPoint[] propulsionMounts;

	/// index of the first polygon in hullModel that is drawn on top of all propulsors
	int elevatedHullShapeIdx = 1;

	/// Built-in hydrophones
	HydrophoneTemplate[] hydrophones;

	/// Built-in active sonar
	SonarTemplate sonar;
}

/// Weapons need to be configured before launch. This is a set of available parameters.
/// Bit flags.
enum WeaponParamType: ushort
{
	none = 0,				/// no weapon params available
	marchCourse = 1,		/// march course.
	sensorMode = 1 << 1,
	marchSpeed = 1 << 2, 	/// speed before activation
	activeSpeed = 1 << 3,	/// speed after activation
	searchPattern = 1 << 4,
	activationRange = 1 << 5,
	activeCourse = 1 << 6	/// main search direction after activation
}

/// Available weapon sensor modes. Bit flags.
enum WeaponSensorMode: ubyte
{
	active = 1,
	passive = 2,
	activePassive = 4		/// alternating active/passive search
}

/// Generic clamped float
struct MinMax
{
	float min = 0.0f;
	float max = 0.0f;

	bool contains(float val) const
	{
		return (val <= max) && (val >= min);
	}
}

/// Bit flags of available search patterns.
enum WeaponSearchPattern: ubyte
{
	straight = 1,
	snake = 2,
	spiral = 4
}

/// Description of search patterns, hard-coded for a weapon
struct WeaponParamDescSearchPatterns
{
	WeaponSearchPattern availablePatterns;
	float snakeWidth = 0.0f;
	float spiralStep = 0.0f;	/// each spiral loop radius is increased by this many meters
}

/// Tagged union of weapon parameter descriptions
struct WeaponParamDesc
{
	WeaponParamType type;
	union
	{
		MinMax speedRange;	/// specified when type is marchSpeed or activeSpeed
		MinMax activationRange;
		WeaponSensorMode sensorModes;
		WeaponParamDescSearchPatterns searchPatterns;
	}
}

/// Tagged union of weapon parameter values, required upon weapon launch.
struct WeaponParamValue
{
	WeaponParamType type;
	union
	{
		float course;
		float speed;
		float range;
		WeaponSensorMode sensorMode;
		WeaponSearchPattern searchPattern;
	}
}

/// Self-propelled weapon
struct WeaponTemplate
{
	/// unique human-readable name
	string name;

	/// description to present to the player on prepare screen
	string description;

	/// hull model. First elements are drawn first.
	ConvexPolygon[] hullModel;

	/// Approximate turning radius, useful for firing solution calculations
	float turningRadius;

	/// Set of available launch parameters
	WeaponParamType availableParams;

	/// Detailed descriptions of available launch parameters, if applicable
	WeaponParamDesc[] paramDescs;
}

struct WeaponSet
{
	int id;		/// submarine-unique id
	/// set of weapon names that can be loaded into the tubes wich are bound
	/// to this set.
	string[] weaponNames;
}

/// Torpedo tube
struct TorpedoTubeTemplate
{
	int id; 	/// submarine-unique id of the tube
	MountPoint mount;
	/// submarine-unique id of torpedo room. Only weapons from this room can be loaded
	/// into this tube.
	int roomId;
	/// submarine-unique id of allowed weapon set. There may be more restrictions
	/// that are bound to the torpedo room.
	int allowedWeaponSetId;
}

/// Torpedo storage
struct TorpedoRoomTemplate
{
	int id;			/// submarine-unique id of the room
	/// human-readable name of the room
	string name;
	/// id of a set of weapons that can be stored in this room
	int allowedWeaponSetId;
	/// max number of weapons that can be stored in this room
	int capacity;
}

/// Some rigid body kinematics at specific time
struct KinematicSnapshot
{
	usecs_t atTime;		/// game-world time
	vec2d position;
	vec2d velocity;
	double rotation;
	double angVel;
}

enum HydrophoneType: byte
{
	/// both broadband and narrowband data available, operator
	/// can listen to raw signal in one direction.
	STANDARD,
	/// Only broadband data is present, no raw signal is streamed
	BROADBANDONLY
}

struct HydrophoneTemplate
{
	/// short name to diplay in selectors
	string name;
	HydrophoneType type;
	MountPoint mount;
	/// field of view of a single antennae, radians
	float fov = 0.0f;
	/// antennae rotations relative to mount rotation.
	/// length of this array is equal to number of antennaes in
	/// the hydrophone.
	float[] antRots;
}

struct SonarTemplate
{
	MountPoint mount;
	/// field of view of the transducer array, radians
	float fov;
	/// maximum ping intensity level
	float maxPingIlevel;
	/// minimum ping intensity level
	float minPingIlevel;
	/// number of pixels in image row
	int resol;
	/// each 1-second image slice will have this many pixel rows
	int radResol;
	/// there will be this many slices for each ping
	int maxDuration;
}

struct SonarSliceData
{
	/// index of the sonar in SubmarineTemplate
	int sonarIdx;
	/// incremented for each ping of this sonar, starts with 0
	int pingId;
	/// incremented for each slice of this ping, starts with 0
	int sliceId;
	/// Each byte is pixel. Screen-space coordinates assumed, 0 index is
	/// top-left corner
	ubyte[] data;
}

/// sound intensity level data from some antennae
struct AntennaeData
{
	int antennaeIdx;	// index of the antennae on that hydrophone
	/// Each sample corresponds to one antennae beam.
	/// Units are decibells, scaled to [0, ushort.max] interval.
	/// Rotation from first beam to last one is clockwise.
	ushort[] beams;
}

struct HydrophoneData
{
	int hydrophoneIdx;	// index of the sub's hydrophone
	AntennaeData[] antennaes;
}

/// hydrophone time-domain sound signal
struct HydrophoneAudio
{
	int hydrophoneIdx;
	float listenDir;	// world-space direction of the beam
	short[] samples;	// 16-bit PCB mono
	int samplingRate;	// usually 4096 Hz
}