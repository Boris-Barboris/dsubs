module dsubs_server.entitydb;

import std.digest.sha;

import dsubs_common.api;

import dsubs_server.common;


immutable EntityDbRes g_commonEntityDb;
immutable(ubyte[]) g_marshalledCommonEntityDb;
immutable(ubyte[]) g_commonEntityDbHash;

shared static this()
{
	g_commonEntityDb = cast(immutable EntityDbRes) EntityDbRes(
		[standardScrew],
		[nooberSub]
	);
	g_marshalledCommonEntityDb = marshalMessage(&g_commonEntityDb);
	auto sha256 = new SHA256Digest();
	sha256.put(g_marshalledCommonEntityDb);
	g_commonEntityDbHash = cast(immutable(ubyte[])) sha256.finish();
	assert(g_commonEntityDbHash.length == 32);
}

private:

Vector2f[] xSymmetry(float[] coords)
{
	assert(coords.length % 2 == 0);
	int len = coords.length / 2;
	Vector2f[] res;
	for (int i = 0; i < len; i++)
		res ~= Vector2f(coords[i*2], coords[i*2 + 1]);
	for (int i = len - 2; i > 0; i--)
		res ~= Vector2f(-coords[i*2], coords[i*2 + 1]);
	return res;
}

PropulsorTemplate standardScrew = PropulsorTemplate(
	"Standard screw",
	"Five-bladed screw with no outstanding traits, " ~
	"but comparatively good high-speed performance.",
	PropulsorType.SCREW,
	5,
	ConvexPolygon([
		Vector2f(1.1f, 0.6f),
		Vector2f(0.6f, -0.6f),
		Vector2f(4.2f, -0.9f)
	], RgbaColor(67, 67, 67), 0.2f, RgbaColor(40, 40, 40))
);

SubmarineTemplate nooberSub = SubmarineTemplate(
	"Aspirant",
	`Light attack submarine "Aspirant" offers good balance of stealth, ` ~
	"offensive power and survivability to rookie captains.",
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