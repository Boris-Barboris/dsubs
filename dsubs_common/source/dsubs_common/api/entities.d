module dsubs_common.api.entities;

import dsubs_common.api.constants;
import dsubs_common.api.utils;


struct RgbaColor
{
	ubyte r, g, b, a;
}

struct ConvexPolygon
{
	Vector!(float, 2)[] points;
	RgbaColor fillColor;
	float borderWidth;
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
	@MaxLenAttr(64) string name;

	/// description of this propulsor
	string description;

	PropulsorType type;

	/// 1 screw blade for screws, whole pump for pumps
	ConvexPolygon model;
}

struct MountPoint
{
	Vector!(float, 2) mountCenter;
	float rotation;
	float scale;
	bool underHull;		// true when this mount point should be drawn before hull
}

/// Playable submarine template
struct SubmarineTemplate
{
	/// human-readable name
	@MaxLenAttr(64) string name;

	/// description to present to the player on prepare screen
	string description;

	/// main hull model. First element is the deepest (drawn first) one.
	ConvexPolygon[] hullModel;

	/// mount points for screws.
	MountPoint[] propulsionMounts;

	/// torpedo tube mounts
	MountPoint[] tubeMounts;
}

/// Self-propelled weapon
struct WeaponTemplate
{
	/// human-readable name
	@MaxLenAttr(64) string name;

	/// description to present to the player on prepare screen
	string description;

	/// hull model. First elements are drawn first.
	ConvexPolygon[] hullModel;
}