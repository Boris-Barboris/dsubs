module dsubs_server.entitydb;

import std.array: array;
import std.algorithm: map;
import std.digest.sha;
import std.exception;

import dsubs_common.api;
import dsubs_common.api.protocols.backend;
import dsubs_common.math;

import dsubs_sound.activesonar;
import dsubs_sound.water: seaNoiseIL;
import dsubs_sound.hydrophone;
import dsubs_sound.modulation;
import dsubs_sound.soundsource;
import dsubs_sound.image;
import dsubs_sound.common: GLOBAL_SRATE;

import dsubs_server.common;
import dsubs_server.propulsion;
import dsubs_server.dynamics;
import dsubs_server.player: Player;
public import dsubs_server.submarine;
public import dsubs_server.torpedo;



final class EntityDb
{
	/// pre-marshalled entity database, ready to be send to user
	const immutable(ubyte)[] marshalledCommonEntityDb;

	/// hash (SHA-256) of g_marshalledCommonEntityDb
	const immutable(ubyte)[] commonEntityDbHash;

	private
	{
		/// map of all existing propulsor factories
		PropulsorFactory[string] m_propulsors;
		/// global map of all existing submarine factories
		SubmarineFactory[string] m_submarines;
		/// global map of all existing torpedo factories
		TorpedoFactory[string] m_torpedos;
	}

	this()
	{
		info("Building entity database");
		buildPropulsorTemplates();
		buildSubmarineTemplates();
		buildTorpedoTemplates();
		immutable EntityDbRes enititydb = immutable EntityDbRes(
			m_propulsors.values.map!(a => a.tmpl).array,
			m_submarines.values.map!(a => a.tmpl).array,
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
		SubmarineFactory* sp = req.submarineName in m_submarines;
		enforce(sp !is null, "Unknown submarine");
		PropulsorFactory* pp = req.propulsorName in m_propulsors;
		enforce(pp !is null, "Unknown propulsor");
		Propulsor prop = pp.build();
		Submarine sub = sp.build(p, prop);
		trace("built new submarine from request ", req);
		return sub;
	}

	const(TorpedoFactory) getTorpedoFactory(string torpName) const
	{
		return m_torpedos[torpName];
	}

private:


	void buildPropulsorTemplates()
	{
		PropulsorFactory bp;

		// Standard screw
		bp = new PropulsorFactory(
			cast(immutable(PropulsorTemplate)) PropulsorTemplate(
				"Seven-blade screw",
				"Seven-blade screw with no outstanding traits, " ~
				"but relatively good high-speed performance.\n\nMass: 50t",
				PropulsorType.screw,
				7,
				ConvexPolygon([
					vec2f(1.1f, 0.6f),
					vec2f(0.6f, -0.6f),
					vec2f(4.2f, -0.9f)
				], RgbaColor(67, 67, 67), 0.2f, RgbaColor(40, 40, 40))
			));
		bp.posThrustK = RolledF(1600.0f, 20.0f);
		bp.negThrustK = RolledF(600.0f, 10.0f);
		bp.mass = 50.0f;
		bp.shaftRotFreq = 2.19f;
		bp.soundPrototype = PropellerSoundPrototype(
			loadSpectrumFromImageAndWarp(Globals.sctx.queue(0),
				"../dsubs_sound/std_propeller.png", 1.0f, 80, 140),
			loadSpectrumFromImageAndWarp(Globals.sctx.queue(0),
				"../dsubs_sound/std_propeller_cav.png", 1.0f, 60, 140),
			cast(immutable) new TrochoidModulatorParams([
				Harmonic(1.0f, 0.35f),
				Harmonic(2.0f, 0.1f),
				Harmonic(3.0f, 0.01f),
				Harmonic(7.0f, 0.8f)],
				0.5, 0.7, -0.4),
			4.2f, dgr2rad(30), 5.0f, 0.03f, 0.4f
		);
		m_propulsors["Seven-blade screw"] = bp;
	}


	void buildTorpedoTemplates()
	{
		TorpedoFactory tf;
		PropulsorFactory pf;
		WeaponParamDesc[] pdescs;
		WeaponParamDesc pd;

		// Minoga torpedo
		pd.type = WeaponParamType.marchSpeed;
		pd.speedRange = MinMax(20, 29);
		pdescs ~= pd;
		pd.type = WeaponParamType.activeSpeed;
		pdescs ~= pd;
		pd.type = WeaponParamType.activationRange;
		pd.activationRange = MinMax(200, 10_000);
		pdescs ~= pd;
		pd.type = WeaponParamType.searchPattern;
		pd.searchPatterns = WeaponParamDescSearchPatterns(
			cast(WeaponSearchPattern)(
				WeaponSearchPattern.straight |
				WeaponSearchPattern.snake |
				WeaponSearchPattern.spiral),
			400.0f, 200.0f, 200.0f
		);
		pdescs ~= pd;

		pf = new PropulsorFactory(
			cast(immutable(PropulsorTemplate)) PropulsorTemplate(
				"Minoga screw",
				null,
				PropulsorType.screw,
				3,
				ConvexPolygon.init
			));
		pf.posThrustK = RolledF(10.0f, 0.02f);
		pf.rotAcceleration = 0.5f;
		pf.negThrustK = RolledF(0.0f, 0.0f);
		pf.mass = 0.0f;
		pf.shaftRotFreq = 21.45f;
		pf.soundPrototype = PropellerSoundPrototype(
			loadSpectrumFromImageAndWarp(Globals.sctx.queue(0),
				"../dsubs_sound/minoga.png", 1.0f, 60, 110),
			loadSpectrumFromImageAndWarp(Globals.sctx.queue(0),
				"../dsubs_sound/minoga_cav.png", 1.0f, 50, 140),
			cast(immutable) new TrochoidModulatorParams([
				Harmonic(1.0f, 0.25f),
				Harmonic(3.0f, 0.75f)],
				0.5, 0.7, -0.4),
			0.25f, dgr2rad(30), 5.0f, 0.03f, 0.7f
		);

		tf = new TorpedoFactory(
			cast(immutable(WeaponTemplate)) WeaponTemplate(
				"Minoga",
				"Minoga torpedo",
				[],
				90.0f,
				cast(WeaponParamType)(
					WeaponParamType.activeCourse |
					WeaponParamType.marchCourse |
					WeaponParamType.activeSpeed |
					WeaponParamType.marchSpeed |
					WeaponParamType.searchPattern |
					WeaponParamType.activationRange),
				pdescs.dup),
			pf);
		tf.propMount.mountCenter = vec2d(0, -2.55);
		tf.sensorsMount.mountCenter = vec2d(0, 2.5);
		// minoga's active sonar
		tf.asprot = new ActiveSonarPrototype();
		tf.asprot.pingParams = PingParameters(
			[Chirp(3600, 3600, 0.1f)], 3, 3600, "octaveHp3500");
		tf.asprot.maxPeakIlevel = tf.asprot.minPeakIlevel = 197.0f;
		tf.asprot.omniBeamCount = 90;
		tf.asprot.waterReflectivity = 0.0f;
		tf.asprot.reflRangeNoise = 100 / 1e4;
		tf.asprot.perlinCellSize = [23, 11];
		tf.asprot.flowNoiseGain = 0.0f;
		tf.asprot.baseNoise = 1.5f;
		tf.asprot.pingDirPower = 2.4f;
		tf.asprot.dissMod = 1.0f;
		tf.asprot.span = 120.0f;
		tf.asprot.radialRes = 20;
		tf.asprot.maxSec = 3;
		tf.asprot.zeroLevel = dB(seaNoiseIL(3600).val + 80.0f);
		tf.asprot.endScale = 0.02f;
		tf.detonationSoundProto = PrerecordedSoundPrototype(
			Globals.sctx.getWavFile("../dsubs_sound/explosion1_8192.wav"),
			40.0f, 145.0f, 2e-3f);

		tf.defaultSensorMode = WeaponSensorMode.active;
		tf.fuelEffExponent = 2.5f;
		tf.snakeArm = 300.0f;
		tf.snakeArmInitial = -40.0f;
		tf.snakeAngle = dgr2rad(60.0f);
		tf.spiralStartTarget = 1.0f;
		tf.spiralTargetRedPerRange = 0.08f;
		float tgtMaxSpeed = 29.0f;
		tf.fuel = RolledF(7000 / tgtMaxSpeed, 2);
		tf.mass = RolledF(1.5f, 2e-3);
		tf.Cd0 = RolledF(0.2f, 1e-3f);
		tf.Cd1 = RolledF(
			(pf.posThrustK.mean - tf.Cd0.mean * tgtMaxSpeed) / pow(tgtMaxSpeed, 2), 3e-4f);
		tf.Cda = 1.5f;
		tf.equilDrift = dgr2rad(10);
		double cl = calcClForTurningRadius(tf.equilDrift,
			tf.tmpl.turningRadius, tf.mass.mean);
		tf.Cl = RolledF(cl, 0.01f * cl);
		tf.Cr0 = RolledF(0.01f, 0);
		tf.Cr1 = RolledF(0, 0);
		tf.Cm = RolledF(0.003f, 0);
		tf.rudderKp = 10.0f;
		tf.rudderKd = -30.0f;
		tf.rudderPosChangeSpeed = 2.0f;
		// vec2f dims = getHullDims(tf.tmpl.hullModel);
		tf.hullLength = 5.2f;
		tf.reflprot = ReflectorPrototype(vec2f(0.6f, 5.2f), [-29.0f, -22.0f, -15.0f]);
		m_torpedos["Minoga"] = tf;

		pdescs.length = 0;
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
  Bow: passive spherical array, 210 deg FoV
Active sonar:
  Bow: 2200Hz mid-freq pulse, 210 deg FoV`,
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
						"bow", HydrophoneType.standard,
						MountPoint(vec2f(0.0f, 31.0f)),
						dgr2rad(210), [0.0f]
					)
				],
				SonarTemplate(MountPoint(vec2f(0.0f, 31.0f)),
					asp.span.dgr2rad, asp.maxPeakIlevel, asp.minPeakIlevel,
					asp.getSliceXResol(), asp.radialRes, asp.maxSec)
			));
		sp.mass = RolledF(1700.0f, 10.0f);
		sp.Cd0 = RolledF(5.0, 0.1f);
		sp.Cd1 = RolledF(5.6, 0.07f);
		sp.Cda = 0.8;
		sp.Cl = RolledF(35.0, 0.4f);
		sp.Cr0 = RolledF(5e4, 100);
		sp.Cr1 = RolledF(0.5e6, 1e2);
		sp.Cm = RolledF(500.0f, 6.0f);
		sp.equilDrift = dgr2rad(20);
		vec2f dims = getHullDims(sp.tmpl.hullModel);
		// trace("dims: ", dims);
		sp.hullLength = dims.y;
		sp.hprots = [
			HydrophonePrototype([0.0f], 250, GLOBAL_SRATE / 2, dgr2rad(210),
			210, 2 / 90.0f, 3.0f)
		];
		sp.asprot = asp;
		sp.reflprot = ReflectorPrototype(vec2f(12.0f, 80.0f), [-25.0f, -19.0f, -10.0f]);
		m_submarines[sp.tmpl.name] = sp;
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