module dsubs_common.api.entities;

import dsubs_common.api.constants;
import dsubs_common.api.utils;


struct RgbaColor
{
	ubyte r, g, b;
	ubyte a = 255;
}

struct ConvexPolygon
{
	Vector2f[] points;	/// counter-clock wise
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
	@MaxLenAttr(64) string name;

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
	bool underHull;		// true when this mount point should be drawn behind hull
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

	/// index of the first polygon in hullModel that is drawn on top of all propulsors
	int elevatedHullShapeIdx = 1;

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