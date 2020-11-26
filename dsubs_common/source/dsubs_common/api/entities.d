module dsubs_common.api.entities;

static import std.algorithm.comparison;

import std.datetime.systime;
import std.conv: to;
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
	screw,
	pump
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

	/// Revolutions per second on 100% thrust.
	float flankRps = 0.0f;

	/// Normalized acceleration of shaft angular velocity
	float throttleSpd = 0.2f;
}

struct MountPoint
{
	vec2f mountCenter = vec2d(0.0f, 0.0f);
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

	/// Allowed propulsors.
	string[] propulsors;

	/// All ammo rooms.
	AmmoRoomTemplate[] ammoRooms;

	/// Both torpedo and decoy tubes.
	TubeTemplate[] tubes;
}

/// Weapons need to be configured before launch. This is a set of available parameters.
/// Bit flags.
enum WeaponParamType: ushort
{
	none = 0,				/// no weapon params available
	marchCourse = 1,		/// march/RTE course.
	sensorMode = 1 << 1,
	marchSpeed = 1 << 2, 	/// speed before activation. RTE speed.
	activeSpeed = 1 << 3,	/// speed after activation
	searchPattern = 1 << 4,
	activationRange = 1 << 5,
	activeCourse = 1 << 6	/// main search direction after activation
}

/// Available weapon sensor modes. Bit mask.
enum WeaponSensorMode: ubyte
{
	active = 1,
	passive = 2,
	activePassive = 4,		/// alternating active/passive search
	dumb = 8
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

	float clamp(float val) const
	{
		return std.algorithm.comparison.max(min,
			std.algorithm.comparison.min(max, val));
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
	float spiralFirstRadius = 0.0f;
	float spiralStep = 0.0f;	/// each spiral loop radius is increased by this many meters
}

union WeaponParamDescUnion
{
	MinMax speedRange;	/// specified when type is marchSpeed or activeSpeed
	MinMax activationRange;
	WeaponSensorMode sensorModes;
	WeaponParamDescSearchPatterns searchPatterns;
}

/// Tagged union of weapon parameter descriptions
struct WeaponParamDesc
{
	WeaponParamType type;
	WeaponParamDescUnion value;
	alias value this;
}

union WeaponParamValueUnion
{
	float course;
	float speed;
	float range;
	WeaponSensorMode sensorMode;
	WeaponSearchPattern searchPattern;
}

/// Tagged union of weapon parameter values, required upon weapon launch.
struct WeaponParamValue
{
	WeaponParamType type;
	WeaponParamValueUnion value;
	alias value this;
}

/// Self-propelled weapon
struct WeaponTemplate
{
	/// unique human-readable name
	string name;

	/// description to present to the player on prepare screen
	string description;

	/// Approximate turning radius, useful for firing solution calculations
	float turningRadius;

	/// Set of available launch parameters
	WeaponParamType availableParams;

	/// Detailed descriptions of launch parameters, if applicable.
	WeaponParamDesc[] paramDescs;

	/// Abstract fuel counter that the client should reduce while integrating
	/// the predicted trajectory.
	float fuel = 0.0f;

	/// Maximum speed that is achieved by setting propulsor's throttle to 1.0f;
	/// Used in fuel calculations.
	float fullThrottleSpd = 0.0f;

	// Torpedo fuel is depleted each second by the formula:
	// float fuelSpent = pow(m_torpedo.propulsor.throttle.fabs, m_fuelExponent);
	// m_fuelLeft -= fuelSpent;
	float fuelExponent = 0.0f;
}

struct WeaponSet
{
	string[] weaponNames;
}

struct WeaponCount
{
	string weaponName;
	int count;
}

enum TubeType: ubyte
{
	standard,		/// standard tube for most types of torpedoes.
	decoy			/// simplified state machine for decoys
}

/**
Standard tube launch state schedule:
	dry -> loading -> dry -> flooding -> flooded -> opening ->
		open -> firing -> open -> closing -> flooded ->
		drying -> dry.
*/
enum TubeState: ushort
{
	// stable states
	dry = 0,
	flooded = 1,
	open = 2,
	// following states are unstable transition states
	loading,	/// weapon is being loaded
	unloading,	/// weapon is being unloaded
	// only loading and unloading states are reversible, that is you can abort unloading
	// and load currently loaded weapon back with less time spent.
	flooding,
	drying,
	opening,
	closing,
	firing
}

bool isStableState(TubeState s)
{
	return s <= TubeState.open;
}

bool isTransientState(TubeState s)
{
	return s > TubeState.open;
}

struct TubeTemplate
{
	int id; 	/// submarine-unique id of the tube
	MountPoint mount;
	/// submarine-unique id of ammo room. Only weapons from this room can be loaded
	/// into this tube.
	int roomId;
	TubeType type;
	/// when true, you can select the ammunition that will be loaded
	bool loadedOnSpawn;
}

struct TubeSpawnState
{
	int tubeId;
	string loadedWeapon;	/// empty string when the tube is empty
}

struct TubeFullState
{
	int tubeId;
	string loadedWeapon;
	string desiredWeapon;
	TubeState currentState;
	TubeState desiredState;
}

/// Torpedo/decoy storage
struct AmmoRoomTemplate
{
	int id;		/// submarine-unique id of the room
	/// submarine-unique human-readable name of the room
	string name;
	WeaponSet allowedWeaponSet;
	/// max number of weapons that can be stored in this room
	int capacity;
}

struct AmmoRoomFullState
{
	int roomId;
	WeaponCount[] storedWeapons;

	int[string] toWeaponCountDict() const
	{
		int[string] res;
		foreach (wc; storedWeapons)
			res.update(wc.weaponName, { return wc.count; },
				(ref int count) { return count + wc.count; });
		return res;
	}
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

enum HydrophoneType: ubyte
{
	/// Hydrophone is hard-mounted to the hull.
	fixed,
	/// Hydrophone is towed.
	towed
}

struct HydrophoneTemplate
{
	/// short name to diplay in selectors
	string name;
	HydrophoneType type;
	/// Focal point for fixed hydrophone, wire mount for towed array
	MountPoint mount;
	/// field of view of a single antennae, radians
	float fov = 0.0f;
	/// antennae rotations relative to mount rotation.
	/// length of this array is equal to number of antennaes in
	/// the hydrophone.
	float[] antRots;
	/// max wire length in case of towed hydrophone.
	float maxWireLength = 0.0f;
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
	/// world position of the hydrophone's focal point
	vec2d position;
	/// world rotation
	double rotation;
}

/// hydrophone time-domain sound signal
struct HydrophoneAudio
{
	int hydrophoneIdx;
	float listenDir;	// world-space direction of the beam
	short[] samples;	// 16-bit PCB mono
	int samplingRate;	// 8192 Hz
}


// Tactical map scenario elements:

enum MapElementType: ubyte
{
	circle,
	text,
	lineSegment
}

struct MapCircle
{
	/// world-space center
	vec2d center;
	/// world-space radius
	double radius;
	/// screen-space line width
	float borderWidth;
}

struct MapText
{
	/// world-space center
	vec2d center;
	int fontSize;
}

// Flexible enough to build arbitrary shapes.
struct MapLineSegment
{
	// world-space points
	vec2d p1;
	vec2d p2;
	/// screen-space line width
	float width;
}

union MapElementUnion
{
	MapCircle circle;
	MapText text;
	MapLineSegment lineSegment;
}

struct MapElement
{
	MapElementType type;
	MapElementUnion value;
	/// In case of text element this is it's content.
	string textContent;
	RgbaColor color;

	// helper constructors

	static MapElement circle(MapCircle params, RgbaColor color)
	{
		MapElement res;
		res.type = MapElementType.circle;
		res.value.circle = params;
		res.color = color;
		return res;
	}

	static MapElement text(MapText params, RgbaColor color, string content)
	{
		MapElement res;
		res.type = MapElementType.text;
		res.value.text = params;
		res.color = color;
		res.textContent = content;
		return res;
	}

	static MapElement lineSegment(MapLineSegment params, RgbaColor color)
	{
		MapElement res;
		res.type = MapElementType.circle;
		res.value.lineSegment = params;
		res.color = color;
		return res;
	}
}



long longUnixTime()
{
	return Clock.currTime.toUnixTime.to!long;
}

enum ChatMessageType: ubyte
{
	/// Sent by scenario running in server simulator.
	scenarioNotice,
	/// Sent by player. Sender receives his own messages.
	playerChat
}

struct ChatMessage
{
	/// unix timestamp, generated by longUnixTime()
	long sentOnUtc;
	ChatMessageType type;
	string message;
	/// In-lore sender name or player name.
	string senderName;
}


enum ScenarioGoalStatus: ubyte
{
	unreached,
	failed,
	success
}

struct ScenarioGoal
{
	/// immutable id to track goals with changing descriptions
	string id;
	ScenarioGoalStatus status;
	string shortText;
	string longDescription;
}


struct WirePointSnapshot
{
	/// world position delta of this point relative to the wire's attach position.
	vec2f position;
	vec2f velocity;
}

struct WireSnapshot
{
	usecs_t atTime;
	/// world position of the attachment point
	vec2d attachPosition;
	/// if empty, no wire segments are extended
	WirePointSnapshot[] points;
}

/// Uncompressed entitydb.
struct EntityDb
{
	PropulsorTemplate[] propulsors;
	SubmarineTemplate[] controllableSubs;
	WeaponTemplate[] weapons;
}

struct EntityDbShort
{
	string[] controllableSubNames;
	string[] propulsorNames;
	string[] weaponNames;
}


// replay-related

enum ReplayObjectType: ubyte
{
	unknown,
	submarine,
	weapon,
	decoy,
	animal
}

struct ReplayObjectRecord
{
	ReplayObjectType type;
	bool dead;
	/// hull/species name.
	string prototype;
	/// captain name or animal name.
	string name;
	vec2f position;
	vec2f velocity;
}

struct ReplaySlice
{
	/// unix timestamp in seconds
	long unixTime;
	ReplayObjectRecord[] objects;
}


// scenario-related entities

enum ScenarioType: ubyte
{
	/// Special scenario that has a persistent simulator instance serving it.
	persistentSimulator,
	tutorial,
	campaignMission,
	standalone
}

/// Collection of missions that must be completed one-by-one.
struct AvailableCampaign
{
	string name;
	string description;
	/// the player has completed all missions earlier.
	bool completed;
	/// Only available scenarios are listed here. Unknown number is hidden.
	AvailableScenario[] scenarios;
}

/// Parts of AvailableScenario that do not depend on the observer.
struct AvailableScenarioConstants
{
	/// Globally-unique human-readable scenario name.
	string name;
	string shortDescription;
	string fullDescription;
	/// part of the entityDb that is allowed for usage in this scenario.
	EntityDbShort allowedEntities;
}

struct AvailableScenario
{
	AvailableScenarioConstants constants;
	/// Type of the scenario.
	ScenarioType type;
	/// true if the user has a record of completion.
	bool completed;
	/// When type is persistentSimulator, this is the id of the sim to spawn in.
	string simulatorId;
	/// For persistent scenarios this is the approximate number of players that are
	/// connected to it's simulator.
	int playerCount;

	alias constants this;
}

enum SpawnRequestType: ubyte
{
	/// Used for persistentSimulator scenarios when the client wishes to spawn
	/// in an already-running sim.
	existingSimulator,
	/// Request to create a new simulator for a scenario and spawn there.
	newSimulator
}


/// Scenario-level simulator flow termination reason.
enum SimFlowEndReason: ubyte
{
	death,
	victory,
	defeat
}