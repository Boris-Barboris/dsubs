module dsubs_server.entitydb;

import std.array: array;
import std.algorithm: map;
import std.digest.sha;
import std.exception;

import dsubs_common.api;
import dsubs_common.api.protocols.backend;
import dsubs_common.math;

import dsubs_sound.activesonar;
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
					vec2f(1.1f, 0.6f),
					vec2f(0.6f, -0.6f),
					vec2f(4.2f, -0.9f)
				], RgbaColor(67, 67, 67), 0.2f, RgbaColor(40, 40, 40))
			));
		bp.posThrustK = RolledF(2600.0f, 40.0f);
		bp.negThrustK = RolledF(900.0f, 20.0f);
		bp.mass = 50.0f;
		bp.shaftRotFreq = 2.0f;
		bp.soundPrototype = PropellerSoundPrototype(
			loadSpectrumFromImageAndWarp(Globals.sctx.queue(0),
				"../dsubs_sound/std_propeller.png", 1.0f, 80, 140),
			loadSpectrumFromImageAndWarp(Globals.sctx.queue(0),
				"../dsubs_sound/std_propeller_cav.png", 1.0f, 60, 140),
			cast(immutable) new TrochoidModulatorParams([
				Harmonic(1.0f, 0.2f),
				Harmonic(2.0f, 0.05f),
				Harmonic(3.0f, 0.01f),
				Harmonic(4.0f, 0.001f),
				Harmonic(5.0f, 0.8f)],
				0.5, 0.7, -0.4),
			4.2f, dgr2rad(30), 5.0f, 0.03f, 0.4f
		);
		g_propulsors["Five-blade screw"] = bp;
	}

	void buildSubmarineTemplates()
	{
		SubmarineFactory sp;

		ActiveSonarPrototype asp = ActiveSonarPrototype();
		sp = new SubmarineFactory(
			cast(immutable(SubmarineTemplate)) SubmarineTemplate(
				"Stork",
`Light attack submarine "Stork" offers good balance of stealth, ` ~
`offensive capabilities and survivability.

Length: 70m
Displacement: 1600t
Top speed: 17m/s
Hydrophones:
  Bow: passive 500-2kHz spherical array, 210 deg FoV
Active sonar:
  Bow: 1200Hz mid-freq pulse, 210 deg FoV`,
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
				[MountPoint(vec2f(0.0, -34.0f))],
				1,
				[
					HydrophoneTemplate(
						"bow", HydrophoneType.STANDARD,
						MountPoint(vec2f(0.0f, 14.2f)),
						dgr2rad(210), [0.0f]
					)
				],
				SonarTemplate(MountPoint(vec2f(0.0f, 13.0f)),
					asp.span.dgr2rad, asp.maxPeakIlevel, asp.minPeakIlevel,
					asp.getSliceResol(), asp.radialRes, asp.maxSec)
			));
		sp.mass = RolledF(1600.0f, 10.0f);
		sp.Cd0 = RolledF(10.0, 0.25f);
		sp.Cd1 = RolledF(8.6, 0.1f);
		sp.Cda = 0.8;
		sp.Cl = RolledF(50.0, 0.4f);
		sp.Cr0 = RolledF(5e4, 100);
		sp.Cr1 = RolledF(0.5e6, 1e2);
		sp.Cm = RolledF(250.0f, 4.0f);
		sp.equilDrift = dgr2rad(21);
		vec2f dims = getHullDims(sp.tmpl.hullModel);
		trace("dims: ", dims);
		sp.hullLength = dims.y;
		sp.hprots = [
			HydrophonePrototype([0.0f], 500, 2048, dgr2rad(210), 210, 2 / 90.0f,
				3.0f, 4e-3, 5e-5, 1e-3)
		];
		sp.asprot = asp;
		sp.reflprot = ReflectorPrototype(vec2f(12.0f, 80.0f), [-12.0f, -9.0f, -5.0f]);
		g_submarines[sp.tmpl.name] = sp;
	}

}


private:

/// build axially-symmetric mesh from it's half. 'coords' array should be in form
/// [ x1, y1, x2, y2 ... ]
vec2f[] xSymmetry(const float[] coords)
{
	assert(coords.length >= 4);
	assert(coords.length % 2 == 0);
	int len = coords.length.to!int / 2;
	vec2f[] res;
	for (int i = 0; i < len; i++)
		res ~= vec2f(coords[i*2], coords[i*2 + 1]);
	for (int i = len - 2; i > 0; i--)
		res ~= vec2f(-coords[i*2], coords[i*2 + 1]);
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