module dsubs_server.entitydb;

import std.array: array;
import std.algorithm: map, any, filter;
import std.digest.sha;
import std.range: retro;
import std.exception;

import dsubs_common.api;
import dsubs_common.api.messages;
import dsubs_common.api.marshalling;
import dsubs_common.math;

import dsubs_sound.activesonar;
import dsubs_sound.water: seaNoiseIL, flowNoise;
import dsubs_sound.hydrophone;
import dsubs_sound.modulation;
import dsubs_sound.soundsource;
import dsubs_sound.image;
import dsubs_sound.common: GLOBAL_SRATE;

import dsubs_server.common;
import dsubs_server.propulsion;
import dsubs_server.sensors;
import dsubs_server.dynamics;
import dsubs_server.player: Captain;
public import dsubs_server.submarine;
public import dsubs_server.animal;
public import dsubs_server.torpedo;
public import dsubs_server.weaponry;


alias EntityDbStruct = dsubs_common.api.entities.EntityDb;



final class EntityDb
{
	/// pre-marshalled entity database message, ready to be send to user.
	const immutable(ubyte)[] marshalledCommonEntityDb;

	/// hash (SHA-256) of marshalledCommonEntityDb
	const immutable(ubyte)[] commonEntityDbHash;

	private
	{
		/// map of all existing propulsor factories
		PropulsorFactory[string] m_propulsors;
		/// global map of all existing submarine factories
		SubmarineFactory[string] m_submarines;
		/// global map of all existing torpedo/decoy factories
		WeaponFactory[string] m_weapons;
		/// global map of all existing animal factories
		AnimalFactory[string] m_animals;
	}

	/// Get EntityDbShort that contains all playable entities.
	EntityDbShort getCompleteShortDb() const
	{
		EntityDbShort res;
		res.controllableSubNames = cast(string[]) m_submarines.byValue.filter!(sf => sf.playable).
			map!(sf => sf.name).array;
		res.propulsorNames = cast(string[]) m_propulsors.byValue.filter!(pf => pf.playable).
			map!(pf => pf.name).array;
		res.weaponNames = cast(string[]) m_weapons.byValue.filter!(wf => wf.playable).
			map!(wf => wf.name).array;
		return res;
	}

	PropulsorFactory getPropulsorFactory(string name)
	{
		return m_propulsors[name];
	}

	SubmarineFactory getSubmarineFactory(string name)
	{
		return m_submarines[name];
	}

	WeaponFactory getWeaponFactory(string name)
	{
		return m_weapons[name];
	}

	AnimalFactory getAnimalFactory(string name)
	{
		return m_animals[name];
	}

	this()
	{
		info("Building entity database");
		buildPropulsorTemplates();
		buildSubmarineTemplates();
		buildTorpedoTemplates();
		buildAnimalTemplates();
		immutable EntityDbStruct enititydb = immutable EntityDbStruct(
			m_propulsors.values.filter!(a => a.playable).map!(
				a => cast(immutable) a.tmpl).array,
			m_submarines.values.filter!(a => a.playable).map!(
				a => cast(immutable) a.tmpl).array,
			m_weapons.values.filter!(a => a.playable).map!(
				a => cast(immutable) a.tmpl).array,
		);
		marshalledCommonEntityDb = BackendProtocol.marshal(immutable EntityDbRes(enititydb));
		auto sha256 = new SHA256Digest();
		sha256.put(marshalledCommonEntityDb);
		commonEntityDbHash = cast(immutable(ubyte)[]) sha256.finish();
		assert(commonEntityDbHash.length == 32);
	}

	/// Build submarine object from the Spawn request message
	Submarine buildSubFromLoadout(const SpawnReq req, Captain cpt, bool humanPlayer = false)
	{
		SubmarineFactory* sf = req.submarineName in m_submarines;
		enforce(sf !is null, "Unknown submarine");
		if (humanPlayer)
			enforce(sf.playable, "sub is unplayable");
		PropulsorFactory* pf = req.propulsorName in m_propulsors;
		enforce(pf !is null, "Unknown propulsor");
		if (humanPlayer)
			enforce(pf.playable, "propulsor is unplayable");
		enforce(sf.tmpl.propulsors.any!(p => p == pf.tmpl.name)(),
			"Propulsor not allowed for submarine");
		Propulsor prop = pf.build();
		Submarine sub = sf.build(cpt, prop, req.ammoRoomLoadouts,
			req.loadableTubeLoadouts);
		trace("built new submarine from request ", req);
		return sub;
	}

	const(WeaponFactory) getWeaponFactory(string torpName) const
	{
		return m_weapons[torpName];
	}

	enum int STORK_RELOAD_SECS = 90;
	enum int STORK_FLOOD_SECS = 9;
	enum int STORK_OPEN_SECS = 6;
	enum int STORK_FIRING_SECS = 3;

private:


	void buildPropulsorTemplates()
	{
		PropulsorFactory bp;

		// Standard screw
		bp = new PropulsorFactory();
		bp.name = "Seven-blade screw";
		bp.description = "Seven-blade screw with no outstanding traits, " ~
			"but relatively good high-speed performance.\n\nMass: 50t";
		bp.type = PropulsorType.screw;
		bp.bladeCount = 7;
		bp.model = ConvexPolygon([
					vec2f(1.1f, 0.6f),
					vec2f(0.6f, -0.6f),
					vec2f(4.2f, -0.9f)
				], RgbaColor(67, 67, 67), 0.2f, RgbaColor(40, 40, 40));
		bp.posThrustK = RolledF(2500.0f, 20.0f);
		bp.negThrustK = RolledF(1000.0f, 10.0f);
		bp.mass = 50.0f;
		bp.shaftRotFreq = 2.19f;
		bp.soundPrototype = PropellerSoundPrototype(
			loadSpectrumFromImageAndWarp(Globals.sctx.queue(0),
				"../dsubs_sound/std_propeller.png", 1.0f, 65, 135),
			loadSpectrumFromImageAndWarp(Globals.sctx.queue(0),
				"../dsubs_sound/std_propeller_cav.png", 1.0f, 60, 140),
			cast(immutable) new TrochoidModulatorParams([
				Harmonic(1.0f, 0.35f),
				Harmonic(2.0f, 0.1f),
				Harmonic(3.0f, 0.01f),
				Harmonic(7.0f, 0.8f)],
				0.5, 0.7, -0.4),
			4.2f, dgr2rad(30), 15.0f, 0.03f, 0.4f
		);

		// info(bp.name, " cavitates on throttle ",
		// 	PropellerSound.estCavitationShaftFreq(bp.soundPrototype) / bp.shaftRotFreq);
		bp.playable = true;
		m_propulsors[bp.name] = bp;

		// Five-blade Lima screw
		bp = new PropulsorFactory();
		bp.name = "Five-blade Lima screw";
		bp.description = "High RPM and low cavitation speed, optimized for flank performance.\n\nMass: 30t";
		bp.type = PropulsorType.screw;
		bp.bladeCount = 5;
		bp.model = ConvexPolygon([
					vec2f(0.5f, 0.4f),
					vec2f(0.36f, -0.4f),
					vec2f(2.2f, -0.7f)
				], RgbaColor(67, 67, 67), 0.15f, RgbaColor(40, 40, 40));
		bp.posThrustK = RolledF(2400.0f, 20.0f);
		bp.negThrustK = RolledF(1100.0f, 10.0f);
		bp.mass = 30.0f;
		bp.shaftRotFreq = 4.11f;
		bp.rotAcceleration = 0.36f;
		bp.soundPrototype = PropellerSoundPrototype(
			loadSpectrumFromImageAndWarp(Globals.sctx.queue(0),
				"../dsubs_sound/lima_propeller.png", 1.0f, 75, 135),
			loadSpectrumFromImageAndWarp(Globals.sctx.queue(0),
				"../dsubs_sound/lima_propeller_cav.png", 1.0f, 60, 140),
			cast(immutable) new TrochoidModulatorParams([
				Harmonic(1.0f, 0.30f),
				Harmonic(2.0f, 0.05f),
				Harmonic(3.0f, 0.005f),
				Harmonic(5.0f, 0.76f)],
				0.5, 0.7, -0.4),
			2.2f, dgr2rad(30), 13.0f, 0.03f, 0.4f
		);

		// info(bp.name, " cavitates on throttle ",
		// 	PropellerSound.estCavitationShaftFreq(bp.soundPrototype) / bp.shaftRotFreq);
		bp.playable = true;
		m_propulsors[bp.name] = bp;

		// three-blade civilian screw
		bp = new PropulsorFactory();
		bp.name = "Civilian three-blade screw";
		bp.bladeCount = 3;
		bp.posThrustK = RolledF(2250.0f, 20.0f);
		bp.negThrustK = RolledF(900.0f, 10.0f);
		bp.mass = 40.0f;
		bp.shaftRotFreq = 4.21f;
		bp.soundPrototype = PropellerSoundPrototype(
			loadSpectrumFromImageAndWarp(Globals.sctx.queue(0),
				"../dsubs_sound/civ_propeller.png", 1.0f, 80, 140),
			loadSpectrumFromImageAndWarp(Globals.sctx.queue(0),
				"../dsubs_sound/civ_propeller_cav.png", 1.0f, 60, 140),
			cast(immutable) new TrochoidModulatorParams([
				Harmonic(1.0f, 0.29f),
				Harmonic(2.0f, 0.04f),
				Harmonic(3.0f, 0.8f)],
				0.5, 0.7, -0.4),
			3.4f, dgr2rad(30), 15.0f, 0.03f, 0.4f
		);

		// info(bp.name, " cavitates on throttle ",
		// 	PropellerSound.estCavitationShaftFreq(bp.soundPrototype) / bp.shaftRotFreq);
		bp.playable = false;
		m_propulsors[bp.name] = bp;
	}


	void buildTorpedoTemplates()
	{
		TorpedoFactory tf;
		PropulsorFactory pf;

		// Minoga torpedo

		pf = new PropulsorFactory();
		pf.name = "Minoga screw";
		pf.bladeCount = 3;
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

		tf = new TorpedoFactory(pf);
		tf.name = "Minoga";
		tf.playable = true;
		tf.description = `"Minoga" heavy torpedo.

Sensors: active sonar or passive hydrophone.
Effective speed range (active): 21-29 m/s.
Effective speed range (passive): 21-26 m/s.
Max range (29m/s): 8000m.
Max range (21m/s): 11200m.
Search patterns: straight, snake, spiral.
`;
		tf.turningRadius = 90.0f;
		tf.marchSpeedRange = MinMax(21, 29);
		tf.activeSpeedRange = MinMax(21, 29);
		tf.activationRange = MinMax(200, 11_200);
		tf.sensorModes = cast(WeaponSensorMode) (
			WeaponSensorMode.active | WeaponSensorMode.passive);
		tf.searchPatterns = WeaponParamDescSearchPatterns(
			cast(WeaponSearchPattern)(
				WeaponSearchPattern.straight |
				WeaponSearchPattern.snake |
				WeaponSearchPattern.spiral),
			400.0f, 150.0f, 200.0f);
		tf.propMount.mountCenter = vec2d(0, -2.55);
		tf.sensorsMount.mountCenter = vec2d(0, 2.5);
		// minoga's active sonar
		tf.asprot = new ActiveSonarPrototype();
		tf.asprot.pingParams = PingParameters(
			[Chirp(3600, 3600, 0.1f)], 3, 3600, "octaveHp3500");
		tf.asprot.maxPeakIlevel = tf.asprot.minPeakIlevel = 197.0f;
		tf.asprot.omniBeamCount = 90;
		tf.asprot.waterReflectivity = -100.0f;
		tf.asprot.reflRangeNoise = 100 / 1e4;
		tf.asprot.perlinCellSize = [23, 11];
		tf.asprot.flowNoiseGain = -10.0f;
		tf.asprot.baseNoise = 1.5f;
		tf.asprot.pingDirPower = 2.4f;
		tf.asprot.dissMod = 1.0f;
		tf.asprot.span = 120.0f;
		tf.asprot.radialRes = 20;
		tf.asprot.maxSec = 1;
		tf.asprot.zeroLevel = flowNoise(3600, mps2kts(20)) +
			tf.asprot.flowNoiseGain - 10.0f;
		tf.asprot.endScale = 1.0f / 60.0f;
		tf.detonationSoundProto = PrerecordedSoundPrototype(
			Globals.sctx.getWavFile("../dsubs_sound/explosion1_8192.wav"),
			40.0f, 145.0f, 2e-3f);
		// minoga's passive sonar
		tf.hprot = new HydrophonePrototype([0.0f], 250, 3000, dgr2rad(120),
				30, 4 / 90.0f, 3.0f);
		tf.hydrophoneNoiseMargin = ushort.max / 12;
		tf.hprot.imageBlackLevel = 45.0f;
		tf.hprot.imageWhiteLevel = 80.0f;
		tf.hprot.omniNoiseMult = 0.0025f;
		tf.hprot.localNoiseRangeCutoff = 100.0f;
		tf.hprot.flowNoiseMult = 1e-9f;
		tf.defaultSensorMode = WeaponSensorMode.active;
		tf.fuelEffExponent = 3.0f;
		tf.snakeArm = 300.0f;
		tf.snakeArmInitial = -40.0f;
		tf.snakeAngle = dgr2rad(60.0f);
		tf.spiralStartTarget = 1.0f;
		tf.spiralTargetRedPerRange = 0.08f;
		tf.fullThrottleSpd = 29.0f;
		tf.tgtMaxRangeOnMaxSpd = 8000.0f;
		tf.rigidBody.mass = RolledF(1.5f, 2e-3);
		tf.rigidBody.Cd0 = RolledF(0.2f, 1e-3f);
		tf.rigidBody.Cda = 1.5f;
		tf.rigidBody.Cr0 = RolledF(0.01f, 0);
		tf.rigidBody.Cr1 = RolledF(0, 0);
		tf.rigidBody.Cm = RolledF(0.003f, 0);
		tf.steering.equilDrift = dgr2rad(10);
		tf.steering.rudderKp = 10.0f;
		tf.steering.rudderKd = -30.0f;
		tf.steering.rudderPosChangeSpeed = 2.0f;
		// vec2f dims = getHullDims(tf.tmpl.hullModel);
		tf.rigidBody.hullLength = 5.2f;
		tf.reflprot = ReflectorPrototype(vec2f(0.6f, 5.2f), [-20.0f, -20.0f, -15.0f]);
		tf.prepareDynamicsAndParams();
		m_weapons[tf.name] = tf;

		// Active decoy

		ActiveDecoyFactory adf = new ActiveDecoyFactory();
		adf.name = "Decoy(active)";
		adf.playable = true;
		adf.description = "Active sonar decoy. Lasts approximately 90 seconds.",
		adf.fuel = RolledF(90, 5);
		adf.rigidBody.mass = RolledF(1.0f, 1e-3);
		adf.rigidBody.Cd0 = RolledF(0.05f, 1e-5f);
		adf.rigidBody.Cd1 = RolledF(0.01f, 1e-5f);
		adf.rigidBody.Cda = 0.0f;
		adf.steering.equilDrift = 0.0f;
		adf.rigidBody.Cl = RolledF(0.01f, 0.0f);
		adf.rigidBody.Cr0 = RolledF(0.05f, 0);
		adf.rigidBody.Cr1 = RolledF(0.25f, 0);
		adf.rigidBody.Cm = RolledF(0.005f, 0);
		adf.steering.rudderKp = 0.0f;
		adf.steering.rudderKd = 0.0f;
		adf.rigidBody.hullLength = 4.0f;
		adf.reflprot = ReflectorPrototype(vec2f(0.6f, 4.0f), [-22.0f, -22.0f, -22.0f]);
		adf.activeReflectorProto = ReflectorPrototype(vec2f(30, 30), [-7.0f, -7.0f, -7.0f]);
		adf.generateParamDescs();
		m_weapons[adf.name] = adf;

		// Passive decoy

		PassiveDecoyFactory pdf = new PassiveDecoyFactory();

		pf = new PropulsorFactory();
		pf.name = "Passive decoy sound source";
		pf.bladeCount = 2;
		pf.posThrustK = RolledF(0.0f, 0.0f);
		pf.rotAcceleration = 0.3f;
		pf.negThrustK = RolledF(0.0f, 0.0f);
		pf.mass = 0.0f;
		pf.shaftRotFreq = 3.1f;
		pf.soundPrototype = PropellerSoundPrototype(
			null,
			loadSpectrumFromImageAndWarp(Globals.sctx.queue(0),
				"../dsubs_sound/passive_decoy_cav.png", 1.0f, 65, 140),
			cast(immutable) new TrochoidModulatorParams([
				Harmonic(1.0f, 0.25f),
				Harmonic(2.0f, 0.75f)],
				0.5, 0.7, -0.4),
			1.0f, dgr2rad(30), 2.0f, 0.03f, 1.0f
		);

		pdf.name = "Decoy(passive)";
		pdf.playable = true;
		pdf.propFactory = pf;
		pdf.description = "Passive sonar decoy. Lasts approximately 2 minutes.",
		pdf.fuel = RolledF(120, 5);
		pdf.rigidBody.mass = RolledF(0.9f, 1e-3);
		pdf.rigidBody.Cd0 = RolledF(0.05f, 1e-5f);
		pdf.rigidBody.Cd1 = RolledF(0.01f, 1e-5f);
		pdf.rigidBody.Cda = 0.0f;
		pdf.steering.equilDrift = 0.0f;
		pdf.rigidBody.Cl = RolledF(0.01f, 0.0f);
		pdf.rigidBody.Cr0 = RolledF(0.05f, 0);
		pdf.rigidBody.Cr1 = RolledF(0.25f, 0);
		pdf.rigidBody.Cm = RolledF(0.005f, 0);
		pdf.steering.rudderKp = 0.0f;
		pdf.steering.rudderKd = 0.0f;
		pdf.rigidBody.hullLength = 2.0f;
		pdf.reflprot = ReflectorPrototype(vec2f(0.6f, 4.0f), [-20.0f, -20.0f, -20.0f]);
		pdf.generateParamDescs();
		m_weapons[pdf.name] = pdf;
	}


	void buildSubmarineTemplates()
	{
		SubmarineFactory sp;

		// Stork

		ActiveSonarPrototype asp = ActiveSonarPrototype();
		AmmoRoomPrototype[int] roomProtos;
		roomProtos[0] = AmmoRoomPrototype(0, "bow rack", 16,
			TubeType.standard, ["Minoga": true]);
		roomProtos[1] = AmmoRoomPrototype(1, "decoy rack", 30,
			TubeType.decoy, ["Decoy(active)": true, "Decoy(passive)": true]);
		TubePrototype bowProtoTemplate = TubePrototype(TubeTemplate(0,
			MountPoint(vec2f(-4.7, 25.0), dgr2rad(20)),
			0, TubeType.standard, false),
			cast(usecs_t)STORK_RELOAD_SECS * 1000_000,
			cast(usecs_t)STORK_FLOOD_SECS * 1000_000,
			cast(usecs_t)STORK_OPEN_SECS * 1000_000,
			cast(usecs_t)STORK_FIRING_SECS * 1000_000);
		bowProtoTemplate.openFlowNoiseMult = 3.0f;
		bowProtoTemplate.floodSoundProto = PrerecordedSoundPrototype(
			Globals.sctx.getWavFile("../dsubs_sound/hissing1_8192.wav"),
			4.0f, 80.0f);
		bowProtoTemplate.openSoundProto = PrerecordedSoundPrototype(
			Globals.sctx.getWavFile("../dsubs_sound/hatchopen1_8192.wav"),
			4.0f, 80.0f);
		bowProtoTemplate.firingSoundProto = PrerecordedSoundPrototype(
			Globals.sctx.getWavFile("../dsubs_sound/launch1_8192.wav"),
			4.0f, 95.0f);
		TubePrototype[int] tubeProtos;
		tubeProtos[0] = bowProtoTemplate;
		bowProtoTemplate.tmpl.mount = MountPoint(vec2f(4.7, 25.0), -dgr2rad(20));
		bowProtoTemplate.tmpl.id = 1;
		tubeProtos[1] = bowProtoTemplate;
		TubePrototype decoyTubePrototype = TubePrototype(TubeTemplate(2,
			MountPoint(vec2f(-4.5, -21.0f), dgr2rad(100)),
			1, TubeType.decoy, true),
			cast(usecs_t)60e6, cast(usecs_t)5e6, cast(usecs_t)6e6, cast(usecs_t)3e6);
		decoyTubePrototype.floodSoundProto = PrerecordedSoundPrototype(
			Globals.sctx.getWavFile("../dsubs_sound/hissing2_5sec_8192.wav"),
			4.0f, 75.0f);
		decoyTubePrototype.openSoundProto = PrerecordedSoundPrototype(
			Globals.sctx.getWavFile("../dsubs_sound/hatchopen1_8192.wav"),
			4.0f, 75.0f);
		decoyTubePrototype.firingSoundProto = PrerecordedSoundPrototype(
			Globals.sctx.getWavFile("../dsubs_sound/launch1_8192.wav"),
			4.0f, 90.0f);
		tubeProtos[2] = decoyTubePrototype;
		decoyTubePrototype.tmpl.mount = MountPoint(vec2f(4.5, -21.0f), -dgr2rad(100));
		decoyTubePrototype.tmpl.id = 3;
		tubeProtos[3] = decoyTubePrototype;
		SubHydrophonePrototype[] hydroProtos;
		hydroProtos ~= SubHydrophonePrototype(
			"bow", HydrophoneType.fixed, MountPoint(vec2f(0.0f, 31.0f)),
			HydrophonePrototype([0.0f], 250, GLOBAL_SRATE / 2, dgr2rad(230),
				230, 2 / 90.0f, 3.0f));
		HydrophonePrototype hprotoInternal = HydrophonePrototype(
			[0.0f], 50, 2500, dgr2rad(320), 320, 1.6 / 90.0f, 2.8f);
		hprotoInternal.omniNoiseMult = 0.05f;
		hprotoInternal.localNoiseRangeCutoff = 250.0f;
		hydroProtos ~= SubHydrophonePrototype(
			"towed", HydrophoneType.towed, MountPoint(vec2f(6.0f, -35.0f)),
			hprotoInternal);
		hydroProtos[$-1].hydroProto.mirrored = true;
		hydroProtos[$-1].hydroProto.filterName = "octaveBp50_2500";
		hydroProtos[$-1].hydroProto.imageBlackLevel = 10.0f;
		hydroProtos[$-1].wirePrototype = AttachedWirePrototype(600.0f, 1);

		sp = new SubmarineFactory();
		sp.name = "Stork";
		sp.description = `Light attack submarine "Stork" offers good balance of stealth,
offensive capabilities and survivability.

Length: 70m
Displacement: 1600t
Top speed:
	Seven-blade screw: 16.8m/s
Armament:
  2x bow torpedo tubes (90 sec reload).
  2x broadside decoy launchers.
Hydrophones:
  Bow: spherical array, 230 deg FoV
  Stern: 600m LF towed array, 330 deg FoV
Active sonars:
  Bow: 2200Hz mid-freq pulse, 210 deg FoV`,
		sp.model = Submarine2DModel(
			[
				// right towed array pylon
				ConvexPolygon(arr2vec2f([
						6.0f, -35.0f,
						6.0f, -34.0f,
						1.0f, -27.0f,
						1.0f, -31.0f
					]), RgbaColor(70, 70, 70), 0.2f, RgbaColor(100, 100, 100)),
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
					]), RgbaColor(67, 67, 67), 0.25f, RgbaColor(50, 50, 50)),
				// bow tubes
				ConvexPolygon([
						vec2f(-5.3, 28.0),
						vec2f(-5.3, 24.0),
						vec2f(-5.0, 24.3),
						vec2f(-5.0, 27.7),
					], RgbaColor(67, 67, 67), 0.15f, RgbaColor(50, 50, 50)),
				ConvexPolygon([
						vec2f(5.0, 27.7),
						vec2f(5.0, 24.3),
						vec2f(5.3, 24.0),
						vec2f(5.3, 28.0)
					], RgbaColor(67, 67, 67), 0.15f, RgbaColor(50, 50, 50)),
				// broadside decoy launchers
				ConvexPolygon([
						vec2f(-5.10, -20.0),
						vec2f(-4.90, -22.0),
						vec2f(-4.60, -21.9),
						vec2f(-4.80, -20.1),
					], RgbaColor(67, 67, 67), 0.15f, RgbaColor(50, 50, 50)),
				ConvexPolygon([
						vec2f(4.80, -20.1),
						vec2f(4.60, -21.9),
						vec2f(4.90, -22.0),
						vec2f(5.10, -20.0)
					], RgbaColor(67, 67, 67), 0.15f, RgbaColor(50, 50, 50)),
			],
			2
		);
		sp.propulsionMounts = [MountPoint(vec2f(0.0, -34.0f))];
		sp.allowedPropulsors = ["Seven-blade screw"];
		sp.roomProtos = roomProtos;
		sp.tubeProtos = tubeProtos;
		sp.rigidBody.mass = RolledF(1700.0f, 10.0f);
		sp.rigidBody.Cd0 = RolledF(40.0, 1.0f);
		sp.rigidBody.Cd1 = RolledF(6.5, 0.042f);
		sp.rigidBody.Cda = 0.8;
		sp.rigidBody.Cl = RolledF(35.0, 0.4f);
		sp.rigidBody.Cr0 = RolledF(5e4, 100);
		sp.rigidBody.Cr1 = RolledF(0.5e6, 1e2);
		sp.rigidBody.Cm = RolledF(500.0f, 6.0f);
		sp.steering.equilDrift = dgr2rad(20);
		vec2f dims = getHullDims(sp.model.hullModel);
		// trace("dims: ", dims);
		sp.rigidBody.hullLength = dims.y;
		sp.hprots = hydroProtos;
		sp.asprot = new SubSonarPrototype(MountPoint(vec2f(0.0f, 31.0f)), asp);
		sp.reflprot = ReflectorPrototype(vec2f(10.0f, 70.0f), [-28.0f, -23.0f, -15.0f]);
		sp.playable = true;
		m_submarines[sp.name] = sp;


		// Lima

		roomProtos = roomProtos.dup;
		roomProtos[0] = AmmoRoomPrototype(0, "bow rack", 14,
			TubeType.standard, ["Minoga": true]);
		roomProtos[1] = AmmoRoomPrototype(1, "decoy rack", 24,
			TubeType.decoy, ["Decoy(active)": true, "Decoy(passive)": true]);
		bowProtoTemplate = TubePrototype(TubeTemplate(0,
			MountPoint(vec2f(-1.0, 25.1), 0.0),
			0, TubeType.standard, false),
			cast(usecs_t)60 * 1000_000,
			cast(usecs_t)STORK_FLOOD_SECS * 1000_000,
			cast(usecs_t)STORK_OPEN_SECS * 1000_000,
			cast(usecs_t)STORK_FIRING_SECS * 1000_000);
		bowProtoTemplate.openFlowNoiseMult = 1.0f;
		bowProtoTemplate.floodSoundProto = PrerecordedSoundPrototype(
			Globals.sctx.getWavFile("../dsubs_sound/hissing1_8192.wav"),
			4.0f, 80.0f);
		bowProtoTemplate.openSoundProto = PrerecordedSoundPrototype(
			Globals.sctx.getWavFile("../dsubs_sound/hatchopen1_8192.wav"),
			4.0f, 80.0f);
		bowProtoTemplate.firingSoundProto = PrerecordedSoundPrototype(
			Globals.sctx.getWavFile("../dsubs_sound/launch1_8192.wav"),
			4.0f, 95.0f);
		tubeProtos = tubeProtos.dup();
		tubeProtos[0] = bowProtoTemplate;
		bowProtoTemplate.tmpl.mount = MountPoint(vec2f(1.0, 25.1), 0.0);
		bowProtoTemplate.tmpl.id = 1;
		tubeProtos[1] = bowProtoTemplate;
		decoyTubePrototype = TubePrototype(TubeTemplate(2,
			MountPoint(vec2f(-2.1, -21.0f), dgr2rad(100)),
			1, TubeType.decoy, true),
			cast(usecs_t)45e6, cast(usecs_t)5e6, cast(usecs_t)6e6, cast(usecs_t)3e6);
		decoyTubePrototype.floodSoundProto = PrerecordedSoundPrototype(
			Globals.sctx.getWavFile("../dsubs_sound/hissing2_5sec_8192.wav"),
			4.0f, 75.0f);
		decoyTubePrototype.openSoundProto = PrerecordedSoundPrototype(
			Globals.sctx.getWavFile("../dsubs_sound/hatchopen1_8192.wav"),
			4.0f, 75.0f);
		decoyTubePrototype.firingSoundProto = PrerecordedSoundPrototype(
			Globals.sctx.getWavFile("../dsubs_sound/launch1_8192.wav"),
			4.0f, 90.0f);
		tubeProtos[2] = decoyTubePrototype;
		decoyTubePrototype.tmpl.mount = MountPoint(vec2f(2.1, -21.0f), -dgr2rad(100));
		decoyTubePrototype.tmpl.id = 3;
		tubeProtos[3] = decoyTubePrototype;
		asp = ActiveSonarPrototype();
		asp.pingParams = PingParameters(
			[Chirp(2400, 2400, 0.2f), Chirp(2100, 2100, 0.5f)],
			3, 2200, "octaveBp1900_2500");
		asp.maxSec = 18;
		asp.maxPeakIlevel = 215.0f;
		asp.minPeakIlevel = 190.0f;
		asp.baseNoise = 2.4f;
		asp.directivity = 17.0f;
		asp.flowNoiseGain = -6.0f;
		asp.reflBearingNoise = 0.029f;
		asp.zeroLevel = dB(seaNoiseIL(2200).val - 23.0f);
		asp.endScale = 1 / 180.0f;
		hydroProtos.length = 0;
		hydroProtos ~= SubHydrophonePrototype(
			"bow", HydrophoneType.fixed, MountPoint(vec2f(0.0f, 23.0f)),
			HydrophonePrototype([0.0f], 250, GLOBAL_SRATE / 2, dgr2rad(210),
				160, 2.0 / 90.0f, 3.5f));
		hydroProtos[0].hydroProto.flowNoiseMult = 2.0e-5f;
		hydroProtos ~= SubHydrophonePrototype(
			"hull", HydrophoneType.fixed, MountPoint(vec2f(0.0f, 0.0f)),
			HydrophonePrototype(
				[dgr2rad(90.0f), -dgr2rad(90.0f)], 200, GLOBAL_SRATE / 2, dgr2rad(120),
				100, 1.5 / 90.0f, 3.4f));
		hydroProtos[1].hydroProto.flowNoiseMult = 1.4e-5f;

	sp = new SubmarineFactory();
	sp.name = "Lima";
	sp.description = `Extremely fast light attack submarine. It's bow is too narrow to
hold reasonably sensitive hydrophone array, so it's main ears are hull-mounted
linear arrays and an active sonar. Favors agressive, non-stealthy combat.

Length: 60m
Displacement: 700t
Top speed:
  Five-blade Lima screw: 21.0m/s
Armament:
  2x bow torpedo tubes (60 sec reload).
  2x broadside decoy launchers.
Hydrophones:
  Bow: spherical array, 210 deg FoV
  Hull: 2 linear arrays, 120 deg FoV each.
Active sonars:
  Bow: 2400Hz mid-freq pulse, 210 deg FoV`;
	sp.model = Submarine2DModel(
		[
			// bow planes
			ConvexPolygon([
					vec2f(-2.88, 20.74),
					vec2f(-5.08, 20.74),
					vec2f(-5.08, 19.45),
					vec2f(-2.89, 19.40)
				], RgbaColor(65, 65, 65), 0.2f, RgbaColor(90, 90, 90)),
			ConvexPolygon([
					vec2f(-2.88, 20.74),
					vec2f(-5.08, 20.74),
					vec2f(-5.08, 19.45),
					vec2f(-2.89, 19.40)
				].xreflect, RgbaColor(65, 65, 65), 0.2f, RgbaColor(90, 90, 90)),
			// tail planes
			ConvexPolygon([
					vec2f(-1.17, -26.37),
					vec2f(-5.23, -27.64),
					vec2f(-5.23, -29.45),
					vec2f(-0.60, -29.48)
				], RgbaColor(65, 65, 65), 0.2f, RgbaColor(90, 90, 90)),
			ConvexPolygon([
					vec2f(-1.17, -26.37),
					vec2f(-5.23, -27.64),
					vec2f(-5.23, -29.45),
					vec2f(-0.60, -29.48)
				].xreflect, RgbaColor(65, 65, 65), 0.2f, RgbaColor(90, 90, 90)),
			// main shape
			ConvexPolygon(xSymmetry([
					0.0, 26.33,
					-0.72, 26.25,
					-1.47, 25.66,
					-2.19, 24.66,
					-2.68, 23.18,
					-2.92, 22.10,
					-3.12, 20.03,
					-3.33, 16.83,
					-3.39, 13.60,
					-3.44, 8.70,
					-3.52, 0.84,
					-3.41, -3.65,
					-3.23, -8.65,
					-2.75, -15.40,
					-1.77, -23.35,
					0.0, -33.44
				]), RgbaColor(70, 70, 70), 0.4f, RgbaColor(100, 100, 100)),
			// sail foundation
			ConvexPolygon(xSymmetry([
					0.0, 11.28,
					-0.60, 10.96,
					-1.42, 9.59,
					-1.94, 7.15,
					-1.72, 3.76,
					-1.16, 0.71,
					0.0, -2.70
				]), RgbaColor(67, 67, 67), 0.25f, RgbaColor(50, 50, 50)),
			// sail roof
			ConvexPolygon(xSymmetry([
					0.0, 10.42,
					-0.21, 10.19,
					-0.79, 9.23,
					-1.06, 7.38,
					-0.85, 3.97,
					-0.48, 1.61,
					0.0, 0.11
				]), RgbaColor(70, 70, 70), 0.2f, RgbaColor(50, 50, 50)),
			// bow tubes
			ConvexPolygon([
					vec2f(-0.85, 25.53),
					vec2f(-1.01, 25.52),
					vec2f(-1.18, 25.39),
					vec2f(-1.26, 25.11),
					vec2f(-1.24, 24.81),
					vec2f(-1.09, 24.45),
					vec2f(-0.87, 24.69),
					vec2f(-0.69, 25.00),
					vec2f(-0.66, 25.25),
					vec2f(-0.70, 25.44)
				], RgbaColor(67, 67, 67), 0.15f, RgbaColor(50, 50, 50)),
			ConvexPolygon([
					vec2f(-0.85, 25.53),
					vec2f(-1.01, 25.52),
					vec2f(-1.18, 25.39),
					vec2f(-1.26, 25.11),
					vec2f(-1.24, 24.81),
					vec2f(-1.09, 24.45),
					vec2f(-0.87, 24.69),
					vec2f(-0.69, 25.00),
					vec2f(-0.66, 25.25),
					vec2f(-0.70, 25.44)
				].xreflect, RgbaColor(67, 67, 67), 0.15f, RgbaColor(50, 50, 50)),
			// broadside decoy launchers
			ConvexPolygon([
					vec2f(-2.50, -20.0),
					vec2f(-2.30, -22.0),
					vec2f(-2.05, -21.9),
					vec2f(-2.25, -20.1),
				], RgbaColor(67, 67, 67), 0.15f, RgbaColor(50, 50, 50)),
			ConvexPolygon([
					vec2f(-2.50, -20.0),
					vec2f(-2.30, -22.0),
					vec2f(-2.05, -21.9),
					vec2f(-2.25, -20.1),
				].xreflect, RgbaColor(67, 67, 67), 0.15f, RgbaColor(50, 50, 50)),
		], 5);
		sp.propulsionMounts = [MountPoint(vec2f(0.0, -34.0f))];
		sp.allowedPropulsors = ["Five-blade Lima screw"];

				// SonarTemplate(MountPoint(vec2f(0.0f, 31.0f)),
				// 	asp.span.dgr2rad, asp.maxPeakIlevel, asp.minPeakIlevel,
				// 	asp.getSliceXResol(), asp.radialRes, asp.maxSec),

		sp.roomProtos = roomProtos;
		sp.tubeProtos = tubeProtos;
		sp.steering.rudderKp = 8.0f;
		sp.steering.rudderKd = -8.0f;
		sp.rigidBody.mass = RolledF(700.0f, 4.0f);
		sp.rigidBody.Cd0 = RolledF(20.0, 0.1f);
		sp.rigidBody.Cd1 = RolledF(4.5, 0.042f);
		sp.rigidBody.Cda = 0.8;
		sp.rigidBody.Cl = RolledF(25.0, 0.1f);
		sp.rigidBody.Cr0 = RolledF(5e4, 100);
		sp.rigidBody.Cr1 = RolledF(0.5e6, 1e2);
		sp.rigidBody.Cm = RolledF(300.0f, 2.0f);
		sp.steering.equilDrift = dgr2rad(20);
		dims = getHullDims(sp.model.hullModel);
		// trace("dims: ", dims);
		sp.rigidBody.hullLength = dims.y;
		sp.hprots = hydroProtos;
		sp.asprot = new SubSonarPrototype(MountPoint(vec2f(0.0f, 23.2f)), asp);
		sp.reflprot = ReflectorPrototype(vec2f(7.0f, 60.0f), [-24.0f, -19.0f, -11.0f]);
		sp.playable = true;
		m_submarines[sp.name] = sp;


		// civilian (bot) trader
		sp = new SubmarineFactory();
		sp.playable = false;
		sp.name = "Bot trader";
		sp.propulsionMounts = [MountPoint(vec2f(0.0, -46.0f))];
		sp.allowedPropulsors = ["Civilian three-blade screw"];
		sp.rigidBody.mass = RolledF(3000.0f, 10.0f);
		sp.rigidBody.Cd0 = RolledF(90.0, 1.0f);
		sp.rigidBody.Cd1 = RolledF(20.0, 0.042f);
		sp.rigidBody.Cda = 0.8;
		sp.rigidBody.Cl = RolledF(50.0, 0.4f);
		sp.rigidBody.Cr0 = RolledF(6e4, 100);
		sp.rigidBody.Cr1 = RolledF(0.6e6, 1e2);
		sp.rigidBody.Cm = RolledF(700.0f, 6.0f);
		sp.steering.equilDrift = dgr2rad(20);
		sp.rigidBody.hullLength = 100;
		sp.reflprot = ReflectorPrototype(vec2f(15.0f, 100.0f), [-8.0f, -5.0f, -4.0f]);
		sp.playable = false;
		m_submarines[sp.name] = sp;
	}


	void buildAnimalTemplates()
	{
		AnimalFactory af = new AnimalFactory();
		af.randomSounds = [
			PrerecordedSoundPrototype(
				Globals.sctx.getWavFile("../dsubs_sound/bio_sounds/whale1_8192.wav"),
				9.0f, 95.0f),
			PrerecordedSoundPrototype(
				Globals.sctx.getWavFile("../dsubs_sound/bio_sounds/whale2_8192.wav"),
				9.0f, 95.0f),
			PrerecordedSoundPrototype(
				Globals.sctx.getWavFile("../dsubs_sound/bio_sounds/whale3_8192.wav"),
				9.0f, 95.0f),
			PrerecordedSoundPrototype(
				Globals.sctx.getWavFile("../dsubs_sound/bio_sounds/whale4_8192.wav"),
				9.0f, 95.0f),
			PrerecordedSoundPrototype(
				Globals.sctx.getWavFile("../dsubs_sound/bio_sounds/whale5_8192.wav"),
				9.0f, 95.0f)
		];
		af.meanSoundPause = cast(usecs_t) 5 * 60 * 1000_000;
		af.soundPauseVariance = cast(usecs_t) 2 * 60 * 1000_000;
		af.mass = 30.0f;
		af.maxSpeed = 7.0f;
		af.reflprot = ReflectorPrototype(vec2f(4.0f, 15.0f), [-20.0f, -20.0f, -20.0f]);
		af.species = "humpback whale";
		m_animals[af.species] = af;

		af = new AnimalFactory();
		af.randomSounds = [
			PrerecordedSoundPrototype(
				Globals.sctx.getWavFile("../dsubs_sound/big_iron_8192.wav"),
				9.0f, 88.0f)
		];
		af.meanSoundPause = cast(usecs_t) 30 * 60 * 1000_000;
		af.soundPauseVariance = cast(usecs_t) 3 * 60 * 1000_000;
		af.mass = 30.0f;
		af.maxSpeed = 6.0f;
		af.reflprot = ReflectorPrototype(vec2f(4.5f, 15.0f), [-18.0f, -18.0f, -18.0f]);
		af.species = "jukebox whale";
		m_animals[af.species] = af;
	}

}


private:

/// build vec2f array from float array
vec2f[] arr2vec2f(const float[] coords)
{
	assert(coords.length >= 2);
	assert(coords.length % 2 == 0);
	int len = coords.length.to!int / 2;
	vec2f[] res;
	for (int i = 0; i < len; i++)
		res ~= vec2f(coords[i*2], coords[i*2 + 1]);
	return res;
}

/// build axially-symmetric mesh from it's half. 'coords' array should be in form
/// [ x1, y1, x2, y2 ... ]
vec2f[] xSymmetry(const float[] coords, bool firstAsMirrorX = false)
{
	assert(coords.length >= 4);
	assert(coords.length % 2 == 0);
	int len = coords.length.to!int / 2;
	vec2f[] res;
	float xPivot = firstAsMirrorX ? coords[0] : 0.0f;
	for (int i = 0; i < len; i++)
		res ~= vec2f(coords[i*2], coords[i*2 + 1]);
	for (int i = len - 2; i > 0; i--)
		res ~= vec2f(xPivot - coords[i*2], coords[i*2 + 1]);
	return res;
}

/// assume that coords describe a complete shape and reflect it
vec2f[] xreflect(const vec2f[] coords)
{
	return coords.retro.map!(c => vec2f(-c.x, c.y)).array;
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
