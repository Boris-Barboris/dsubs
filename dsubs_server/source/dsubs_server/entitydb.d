module dsubs_server.entitydb;

import std.array: array;
import std.algorithm: map;
import std.digest.sha;
import std.exception;

import dsubs_common.api;
import dsubs_common.api.protocols.backend;
import dsubs_common.math;

import dsubs_sound.hydrophone;
import dsubs_sound.modulation;
import dsubs_sound.soundsource;
import dsubs_sound.image;

import dsubs_server.common;
import dsubs_server.propulsion;
import dsubs_server.player: Player;
public import dsubs_server.submarine;



final class EntityDb
{
	/// pre-marshalled entity database, ready to be send to user
	const immutable(ubyte)[] marshalledCommonEntityDb;

	/// hash (SHA-256) of g_marshalledCommonEntityDb
	const immutable(ubyte)[] commonEntityDbHash;

	private
	{
		/// map of all existing propulsor factories
		PropulsorFactory[string] g_propulsors;
		/// global map of all existing submarine factories
		SubmarineFactory[string] g_submarines;
	}

	this()
	{
		info("Building entity database");
		buildPropulsorTemplates();
		buildSubmarineTemplates();
		immutable EntityDbRes enititydb = immutable EntityDbRes(
			g_propulsors.values.map!(a => *a.getTemplate()).array,
			g_submarines.values.map!(a => *a.getTemplate()).array,
		);
		marshalledCommonEntityDb = BackendProtocol.marshal(enititydb);
		auto sha256 = new SHA256Digest();
		sha256.put(marshalledCommonEntityDb);
		commonEntityDbHash = cast(immutable(ubyte)[]) sha256.finish();
		assert(commonEntityDbHash.length == 32);
	}

	/// Build submarine object from the Spawn request message
	Submarine buildSubFromLoadout(const SpawnReq req, Player p)
	{
		SubmarineFactory* sp = req.submarineName in g_submarines;
		enforce(sp !is null, "Unknown submarine");
		PropulsorFactory* pp = req.propulsorName in g_propulsors;
		enforce(pp !is null, "Unknown propulsor");
		Submarine sub = sp.build(p);
		sub.propulsor = pp.build();
		trace("built new submarine from request ", req);
		return sub;
	}

private:

	void buildPropulsorTemplates()
	{
		PropulsorFactory bp;

		// Standard screw
		bp = new PropulsorFactory(
			cast(immutable(PropulsorTemplate)) PropulsorTemplate(
				"Five-blade screw",
				"Five-blade screw with no outstanding traits, " ~
				"but relatively good high-speed performance.\n\nMass: 50t",
				PropulsorType.SCREW,
				5,
				ConvexPolygon([
					Vector2f(1.1f, 0.6f),
					Vector2f(0.6f, -0.6f),
					Vector2f(4.2f, -0.9f)
				], RgbaColor(67, 67, 67), 0.2f, RgbaColor(40, 40, 40))
			));
		bp.posThrustK = RolledF(2600.0f, 40.0f);
		bp.negThrustK = RolledF(700.0f, 20.0f);
		bp.mass = 50.0f;
		bp.soundPrototype = PropellerSoundPrototype(
			loadSpectrumFromImageAndWarp(
				"../dsubs_sound/std_propeller.png", 1.0f).toIntensity,
			loadSpectrumFromImageAndWarp(
				"../dsubs_sound/std_propeller_cav.png", 1.0f).toIntensity,
			AmplitudeModulatorParams(
				[0.2f, 0.01f, 0.007f, 0.009f, 0.18f, 0.006f], 0.0f),
			4.2f, dgr2rad(30), 8.0f, 0.03f
		);
		g_propulsors["Five-blade screw"] = bp;
	}

	void buildSubmarineTemplates()
	{
		SubmarineFactory sp;

		sp = new SubmarineFactory(
			cast(immutable(SubmarineTemplate)) SubmarineTemplate(
				"Nautilus",
`Light attack submarine "Nautilus" offers good balance of stealth, ` ~
`offensive capabilities and survivability.

Length: 70m
Displacement: 2000t
Top speed: 17m/s
Hydrophones:
  Bow: passive 500-2kHz spherical array, 180 deg FoV`,
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
				[
					HydrophoneTemplate(
						"bow", HydrophoneType.STANDARD,
						MountPoint(Vector2f(0.0f, 14.2f)),
						dgr2rad(180), [0.0f]
					)
				]
			));
		sp.mass = RolledF(2000.0f, 10.0f);
		sp.Cd0 = RolledF(9.0, 0.05f);
		sp.Cd1 = RolledF(16.0, 0.1f);
		sp.Cl = RolledF(40.0, 0.4f);
		sp.Cr = RolledF(1.2e6, 1e2);
		sp.Cm = RolledF(250.0f, 4.0f);
		sp.equilDrift = dgr2rad(15);		// ~15 deg
		vec2f dims = getHullDims(sp.tmpl.hullModel);
		trace("dims: ", dims);
		sp.hullLength = dims.y;
		sp.hprots = [
			HydrophonePrototype([0.0f], 500, 2047, dgr2rad(180), 181, 4 / 181.0f)
		];
		g_submarines[sp.tmpl.name] = sp;
	}

}


private:

/// build axially-symmetric mesh from it's half. 'coords' array should be in form
/// [ x1, y1, x2, y2 ... ]
Vector2f[] xSymmetry(const float[] coords)
{
	assert(coords.length >= 4);
	assert(coords.length % 2 == 0);
	int len = coords.length.to!int / 2;
	Vector2f[] res;
	for (int i = 0; i < len; i++)
		res ~= Vector2f(coords[i*2], coords[i*2 + 1]);
	for (int i = len - 2; i > 0; i--)
		res ~= Vector2f(-coords[i*2], coords[i*2 + 1]);
	return res;
}

vec2f getHullDims(const ConvexPolygon[] pols)
{
	float xmin = float.max;
	float xmax = -float.max;
	float ymin = float.max;
	float ymax = -float.max;
	foreach (pol; pols)
	{
		foreach (vec; pol.points)
		{
			if (xmin > vec[0])
				xmin = vec[0];
			if (xmax < vec[0])
				xmax = vec[0];
			if (ymin > vec[1])
				ymin = vec[1];
			if (ymax < vec[1])
				ymax = vec[1];
		}
	}
	return vec2f(xmax - xmin, ymax - ymin);
}