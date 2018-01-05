module dsubs_server.entitydb;

import std.digest.sha;

import dsubs_common.api;

import dsubs_server.common;


__gshared immutable EntityDbRes g_commonEntityDb;
__gshared immutable(ubyte)[] g_marshalledCommonEntityDb;
__gshared immutable(ubyte)[] g_commonEntityDbHash;

shared static this()
{
	g_commonEntityDb = cast(immutable EntityDbRes) EntityDbRes(
		[standardScrew],
		[nooberSub]
	);
	g_marshalledCommonEntityDb = marshalMessage(&g_commonEntityDb);
	auto sha256 = new SHA256Digest();
	sha256.put(g_marshalledCommonEntityDb);
	g_commonEntityDbHash = cast(immutable(ubyte)[]) sha256.finish();
	assert(g_commonEntityDbHash.length == 32);
}

private:

PropulsorTemplate standardScrew = PropulsorTemplate(
	"Standard screw",
	"Flexible, balanced solution for a propulsion problem.",
	PropulsorType.SCREW,
	7,
	ConvexPolygon([
		Vector2f([0.0f, -2.0f]),
		Vector2f([10.0f, -3.0f]),
		Vector2f([0.0f, 2.0f])
	], RgbaColor(60, 60, 60), 0.5f, RgbaColor(100, 100, 100))
);

SubmarineTemplate nooberSub = SubmarineTemplate(
	"Noober",
	"Go swim",
	[
		ConvexPolygon([
			Vector2f([20.0f, 50.0f]),
			Vector2f([-20.0f, 50.0f]),
			Vector2f([-20.0f, -50.0f]),
			Vector2f([20.0f, -50.0f])
		], RgbaColor(50, 50, 50), 3.0f, RgbaColor(100, 100, 100))
	],
	[MountPoint(Vector2f([0.0, -60.0f]))],
	[]
);