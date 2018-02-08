module dsubs_server.entitydb;

import std.array: array;
import std.algorithm: map;
import std.digest.sha;

import dsubs_common.api;

import dsubs_server.common;
import dsubs_server.propulsion;
import dsubs_server.rng;


/// pre-marshalled entity database, ready to be send to user
immutable(ubyte[]) g_marshalledCommonEntityDb;

/// hash (SHA-256) of g_marshalledCommonEntityDb
immutable(ubyte[]) g_commonEntityDbHash;


enum SpawnPermission: byte
{
	player,		// entity can be spawned for player
	npc			// entity is NPC-only
}

//
// Propulsors
//

interface PropulsorPrototype
{
	Propulsor build() const;
	const(PropulsorTemplate)* getTemplate() const;
	SpawnPermission getPermission() const;
}

/// global map of all existing propulsors
immutable(PropulsorPrototype[string]) g_propulsors;

class BasicPropulsorPrototype: PropulsorPrototype
{
	PropulsorTemplate tmpl;
	RolledF posThrustK;
	RolledF negThrustK;
	SpawnPermission permission = SpawnPermission.player;

	BasicPropulsor build() const
	{
		BasicPropulsor res = new BasicPropulsor();
		res.posThrustK = posThrustK;
		res.negThrustK = negThrustK;
		return res;
	}

	const(PropulsorTemplate)* getTemplate() const
	{
		return &tmpl;
	}

	SpawnPermission getPermission() const
	{
		return permission;
	}
}

shared static this()
{
	BasicPropulsorPrototype bp = new BasicPropulsorPrototype();
	bp.tmpl =
		PropulsorTemplate(
			"Standard screw",
			"Five-bladed screw with no outstanding traits, " ~
			"but relatively good high-speed performance.",
			PropulsorType.SCREW,
			5,
			ConvexPolygon([
				Vector2f(1.1f, 0.6f),
				Vector2f(0.6f, -0.6f),
				Vector2f(4.2f, -0.9f)
			], RgbaColor(67, 67, 67), 0.2f, RgbaColor(40, 40, 40))
		);
	bp.posThrustK = RolledF(100.0f, 2.0f);
	bp.negThrustK = RolledF(40.0f, 1.0f);
	g_propulsors["Standard screw"] = cast(immutable PropulsorPrototype) bp;
}


//
// Submarines
//

/// build axially-symmetric mesh from it's own half. 'coords' array should be in form
/// [ x1, y1, x2, y2 ... ]
Vector2f[] xSymmetry(float[] coords)
{
	assert(coords.length >= 4);
	assert(coords.length % 2 == 0);
	int len = coords.length / 2;
	Vector2f[] res;
	for (int i = 0; i < len; i++)
		res ~= Vector2f(coords[i*2], coords[i*2 + 1]);
	for (int i = len - 2; i > 0; i--)
		res ~= Vector2f(-coords[i*2], coords[i*2 + 1]);
	return res;
}

SubmarineTemplate nooberSub = SubmarineTemplate(
	"Bobby",
	`Light attack submarine "Bobby" offers good balance of stealth, ` ~
	"offensive power and survivability.",
	[
		ConvexPolygon(xSymmetry([
				0.0, 35.0,
				-1.5, 34.8,
				-2.8, 34,
				-3.5, 33.0,
				-4, 32.2,
				-4.7, 30.0,
				-5.0, 28.0,
				-5.0, -18.0,
				-4.5, -23.0,
				-3.0, -28.0,
				-2.0, -31.0,
				0.0, -35.0
			]), RgbaColor(70, 70, 70), 0.4f, RgbaColor(100, 100, 100)),
		ConvexPolygon(xSymmetry([
				0.0, 15.0,
				-1.0, 14.7,
				-1.7, 14.0,
				-2.0, 13.0,
				-2.0, 4.0,
				-1.7, 2.0,
				-1.0, 0.5,
				0.0, -1.0
			]), RgbaColor(67, 67, 67), 0.25f, RgbaColor(50, 50, 50))
	],
	[MountPoint(Vector2f(0.0, -34.0f))],
	1,
	[]
);



shared static this()
{
	const EntityDbRes enititydb = const EntityDbRes(
		g_propulsors.values.map!(a => *a.getTemplate()).array,
		[nooberSub]
	);
	g_marshalledCommonEntityDb = marshalMessage(cast(immutable(EntityDbRes)*) &enititydb);
	auto sha256 = new SHA256Digest();
	sha256.put(g_marshalledCommonEntityDb);
	g_commonEntityDbHash = cast(immutable(ubyte[])) sha256.finish();
	assert(g_commonEntityDbHash.length == 32);
}