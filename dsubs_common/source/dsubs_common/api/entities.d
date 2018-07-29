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

/// Reflection-friendly POD vector. Needed because gfm vector uses anonymous union
/// wich I don't even want to bother to reflect correctly.
struct PODVector(T, size_t size)
	if (isNumeric!T)
{
	T[size] data = 0;

	this(T...)(T args)
		if (T.length == size)
	{
		foreach (i, arg; args)
			data[i] = arg;
	}

	/// reinterpret cast to gfm vector
	pragma(inline) Vector!(FT, size) toGfm(FT = T)() const @trusted
	{
		static if (is(FT == T))
			return *cast(Vector!(FT, size)*) &this;
		else
			return Vector!(FT, size)(data);
	}

	ref inout(T) opIndex(size_t i) inout
	{
		return data[i];
	}
}

alias Vector2f = PODVector!(float, 2);
alias Vector2d = PODVector!(double, 2);

unittest
{
	Vector2f vec;
	assert(vec[0] == 0.0f);
	assert(vec[1] == 0.0f);
}

struct ConvexPolygon
{
	Vector2f[] points;	/// counter-clockwise vertices
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
	Vector2f mountCenter;
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
}

/// Self-propelled weapon
struct WeaponTemplate
{
	/// human-readable name
	string name;

	/// description to present to the player on prepare screen
	string description;

	/// hull model. First elements are drawn first.
	ConvexPolygon[] hullModel;
}

/// Some rigid body kinematics at specific time
struct KinematicSnapshot
{
	usecs_t atTime;		/// game-world time
	Vector2d position;
	Vector2d velocity;
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
	/// field of view of a single antennae
	float fov = 0.0f;
	/// antennae rotations relative to mount rotation.
	/// length of this array is equal to number of antennaes in
	/// the hydrophone.
	float[] antRots;
}

/// sound intensity level data from some antennae
struct AntennaeData
{
	int hydrophoneIdx;	// index of the sub's hydrophone
	int antennaeIdx;	// index of the antennae on that hydrophone
	/// Each sample corresponds to one antennae "cell" - directional virtual sensor.
	/// Units are decibells, scaled to [0, ushort.max] interval. Conversion to
	/// ushort is performed to save network bandwidth.
	ushort[] cells;
}