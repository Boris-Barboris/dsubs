module dsubs_server.entitydb;

import std.array: array;
import std.algorithm: map;
import std.digest.sha;
import std.exception;

import dsubs_common.api;

import dsubs_server.common;
import dsubs_server.propulsion;
import dsubs_server.player: PlayerContext;
public import dsubs_server.submarine;
import dsubs_server.rng;


/// pre-marshalled entity database, ready to be send to user
immutable(ubyte[]) g_marshalledCommonEntityDb;

/// hash (SHA-256) of g_marshalledCommonEntityDb
immutable(ubyte[]) g_commonEntityDbHash;


/// build entity database, should be called from shared module constructor
void s_buildEntityDatabase()
{
	info("Building entity database");
	buildPropulsorTemplates();
	buildSubmarineTemplates();
	const EntityDbRes enititydb = const EntityDbRes(
		g_propulsors.values.map!(a => *a.getTemplate()).array,
		g_submarines.values.map!(a => *a.getTemplate()).array,
	);
	// ugly hacks around immutable
	*(cast(immutable(ubyte)[]*) &g_marshalledCommonEntityDb) =
		marshalMessage(cast(immutable(EntityDbRes)*) &enititydb);
	auto sha256 = new SHA256Digest();
	sha256.put(g_marshalledCommonEntityDb);
	*(cast(ubyte[]*) &g_commonEntityDbHash) = sha256.finish();
	assert(g_commonEntityDbHash.length == 32);
}


Submarine buildSubFromLoadout(const SpawnReq req, PlayerContext ctx)
{
	SubmarinePrototype* sp = req.submarineName in g_submarines;
	enforce(sp !is null, "Unknown submarine");
	PropulsorPrototype* pp = req.propulsorName in g_propulsors;
	enforce(pp !is null, "Unknown propulsor");
	Submarine sub = sp.build(ctx);
	sub.propulsor = pp.build();
	return sub;
}


private:


enum SpawnPermission: byte
{
	player,		/// entity can be spawned for player
	npc			/// entity is NPC-only
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

/// global map of all existing propulsor prototypes
__gshared PropulsorPrototype[string] g_propulsors;

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
		res.prototypeName = tmpl.name;
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

void buildPropulsorTemplates()
{
	BasicPropulsorPrototype bp;

	// Standard screw
	bp = new BasicPropulsorPrototype();
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
	bp.posThrustK = RolledF(2400.0f, 40.0f);
	bp.negThrustK = RolledF(600.0f, 20.0f);
	g_propulsors["Standard screw"] = bp;
}


//
// Submarines
//

/// build axially-symmetric mesh from it's half. 'coords' array should be in form
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

interface SubmarinePrototype
{
	Submarine build(PlayerContext pc) const;
	const(SubmarineTemplate)* getTemplate() const;
	SpawnPermission getPermission() const;
}

/// global map of all existing submarine prototypes
__gshared SubmarinePrototype[string] g_submarines;

class BasicSubmarinePrototype: SubmarinePrototype
{
	SubmarineTemplate tmpl;
	// physical characteristics
	RolledF moi, mass, Cd0, Cd1, Cr, Cl;

	/// rudder gain, wich is multiplied on the sub moi when it's built
	float rudderSteerK;
	SpawnPermission permission = SpawnPermission.player;

	Submarine build(PlayerContext pc) const
	{
		Submarine res = new Submarine(pc, tmpl.name);
		res.rigidBody.moi = moi;
		res.rigidBody.mass = mass;
		res.rigidBody.hydroModel.Cd0 = Cd0;
		res.rigidBody.hydroModel.Cd1 = Cd1;
		res.rigidBody.hydroModel.Cr = Cr;
		res.rigidBody.hydroModel.Cl = Cl;
		// FIXME: for now we simply bake rudder into the submarine
		auto brudder = new BasicRudder();
		brudder.steeringK = rudderSteerK * res.rigidBody.moi;
		res.rudder = brudder;
		return res;
	}

	const(SubmarineTemplate)* getTemplate() const
	{
		return &tmpl;
	}

	SpawnPermission getPermission() const
	{
		return permission;
	}
}


void buildSubmarineTemplates()
{
	BasicSubmarinePrototype sp;

	// Standard screw
	sp = new BasicSubmarinePrototype();
	sp.tmpl =
		SubmarineTemplate(
			"Eona",
`Light attack submarine "Eona" offers good balance of stealth, ` ~
`offensive capabilities and survivability.

Length: 70m
Displacement: 3000t,
Top speed: 16m/s`,
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
	sp.moi = RolledF(1000.0f, 5.0f);
	sp.mass = RolledF(3000.0f, 10.0f);
	sp.Cd0 = RolledF(9.0, 0.05f);
	sp.Cd1 = RolledF(15.0, 0.05f);
	sp.Cl = RolledF(100.0, 1.0f);
	sp.Cr = RolledF(10000.0, 10.0f);
	sp.rudderSteerK = 0.0001f;
	g_submarines["Eona"] = sp;
}