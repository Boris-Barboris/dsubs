module dsubs_server.tests.test_guidance;

import std.stdio;
import std.algorithm: min, map;
import std.array: array;

import dsubs_common.api.messages;
import dsubs_common.math;

import dsubs_server.common;
import dsubs_server.entitydb;
import dsubs_server.submarine;
import dsubs_server.simulator;
import dsubs_server.propulsion;
import dsubs_server.torpedo;
import dsubs_sound.activesonar;

import dsubs_server.tests.common;


/*

unittest
{
	auto sim = Globals.buildForTests();
	const TorpedoFactory tf = cast(TorpedoFactory) Globals.entityDb.getWeaponFactory("Minoga");
	WeaponParamValue[] pvs;
	WeaponParamValue pv;

	pv.type = WeaponParamType.course;
	pv.course = dgr2rad(-90.0);
	pvs ~= pv;
	pv.type = WeaponParamType.activationRange;
	pv.range = 400.0f;
	pvs ~= pv;


	Torpedo t = tf.build(null, pvs);
	t.register(sim);
	File* file = writeRbodyCsvHeader("guidance", "minoga_turning", "minoga");
	sim.onSimulationPassStart += captureVesselRbCsv(file, t);
	sim.worldTimeLimit = 40 * cast(ulong)1e6;
	scope(exit) Globals.resetForTests();
	Globals.simulators.start();
	Globals.simulators.join();
}


unittest
{
	Globals.buildForTests();
	const TorpedoFactory tf = cast(TorpedoFactory) Globals.entityDb.getWeaponFactory("Minoga");
	WeaponParamValue[] pvs;
	WeaponParamValue pv;

	// slow torp
	pv.type = WeaponParamType.course;
	pv.course = dgr2rad(-45.0f);
	pvs ~= pv;
	pv.type = WeaponParamType.marchSpeed;
	pv.speed = 21.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.activationRange;
	pv.range = 5000.0f;
	pvs ~= pv;

	Torpedo t = tf.build(null, pvs);
	t.guidance.fuelLeft = 20.0f;
	t.transform.rotation = dgr2rad(-45.0f);
	t.register();
	File* file = writeRbodyCsvHeader("guidance", "minoga_endurance", "minoga21mps");
	Globals.sim.onSimulationPassStart += captureVesselRbCsv(file, t);

	// fast torp
	pvs.length = 0;
	pv.type = WeaponParamType.course;
	pv.course = dgr2rad(-45.0f);
	pvs ~= pv;
	pv.type = WeaponParamType.marchSpeed;
	pv.speed = 29.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.activationRange;
	pv.range = 5000.0f;
	pvs ~= pv;

	t = tf.build(null, pvs);
	t.guidance.fuelLeft = 20.0f;
	t.transform.position = vec2d(50.0, 0);
	t.transform.rotation = dgr2rad(-45.0f);
	t.register();
	file = writeRbodyCsvHeader("guidance", "minoga_endurance", "minoga29mps");
	Globals.sim.onSimulationPassStart += captureVesselRbCsv(file, t);

	Globals.sim.worldTimeLimit = 60 * cast(ulong)1e6;
	scope(exit) Globals.resetForTests();
	Globals.sim.start();
	Globals.sim.join();
}

unittest
{
	Globals.buildForTests();
	const TorpedoFactory tf = cast(TorpedoFactory) Globals.entityDb.getWeaponFactory("Minoga");
	WeaponParamValue[] pvs;
	WeaponParamValue pv;

	pv.type = WeaponParamType.course;
	pv.course = dgr2rad(0.0);
	pvs ~= pv;
	pv.type = WeaponParamType.activationRange;
	pv.range = 400.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.activeSpeed;
	pv.speed = 29.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.searchPattern;
	pv.searchPattern = WeaponSearchPattern.snake;
	pvs ~= pv;

	Torpedo t = tf.build(null, pvs);
	t.register();
	int imageCounter;
	cleanFolderForSonarImages("guidance", "minoga_snake");
	t.guidance.onSonarImageReady += (img, w, h) {
		writeTestImage("guidance", "minoga_snake", "minoga", img, w, h, imageCounter);
		imageCounter++;
	};

	SpawnReq req = SpawnReq("Stork", "Seven-blade screw");
	Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
	double mspd = speedForThrottle(s.rigidBody.hydroModel, cast(BasicPropulsor) s.propulsor);
	s.transform.position = vec2d(-2000, 3000);
	s.transform.rotation = -dgr2rad(90);
	s.rigidBody.kinet.vel = courseVector(s.transform.rotation) * mspd;
	s.targetCourse = s.transform.rotation;
	s.targetThrottle = 1.0f;
	s.register();
	File* storkFile = writeRbodyCsvHeader("guidance", "minoga_snake", "stork");
	Globals.sim.onSimulationPassStart += captureVesselRbCsv(storkFile, s);

	File* minogaFile = writeRbodyCsvHeader("guidance", "minoga_snake", "minoga");
	Globals.sim.onSimulationPassStart += captureVesselRbCsv(minogaFile, t);
	Globals.sim.worldTimeLimit = 300 * cast(ulong)1e6;

	double minDist = double.max;
	Globals.sim.onSimulationPassStart += (now) {
		minDist = min(minDist, (t.transform.wposition - s.transform.wposition).length);
	};

	scope(exit) Globals.resetForTests();
	Globals.sim.start();
	Globals.sim.join();

	trace("minoga was ", minDist, " meters away from stork in minoga_snake test");
	assert(s.dead);
}

*/

/*

unittest
{
	auto sim = Globals.buildForTests();
	const TorpedoFactory tf = cast(TorpedoFactory) Globals.entityDb.getWeaponFactory("Electra");
	WeaponParamValue[] pvs;
	WeaponParamValue pv;

	pv.type = WeaponParamType.course;
	pv.course = dgr2rad(0.0);
	pvs ~= pv;
	pv.type = WeaponParamType.activationRange;
	pv.range = 400.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.activeSpeed;
	pv.speed = 25.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.searchPattern;
	pv.searchPattern = WeaponSearchPattern.snake;
	pvs ~= pv;

	Torpedo t = tf.build(null, pvs);
	t.register(sim);
	int imageCounter;
	cleanFolderForSonarImages("guidance", "electra_snake");
	t.guidance.onSonarImageReady += (img, w, h) {
		writeTestImage("guidance", "electra_snake", "electra", img, w, h, imageCounter);
		imageCounter++;
	};

	SpawnReq req = SpawnReq("Stork", "Seven-blade screw");
	Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
	s.transform.position = vec2d(-2200, 3000);
	s.transform.rotation = -dgr2rad(90);
	s.rigidBody.kinet.vel = courseVector(s.transform.rotation) * 5.0f;
	s.targetCourse = s.transform.rotation;
	s.targetThrottle = 1.0f;
	s.register(sim);
	File* storkFile = writeRbodyCsvHeader("guidance", "electra_snake", "stork");
	sim.onSimulationPassStart += captureVesselRbCsv(storkFile, s);

	File* electraFile = writeRbodyCsvHeader("guidance", "electra_snake", "electra");
	sim.onSimulationPassStart += captureVesselRbCsv(electraFile, t);
	sim.worldTimeLimit = 300 * cast(ulong)1e6;

	double minDist = double.max;
	sim.onSimulationPassStart += (sim, now) {
		minDist = min(minDist, (t.transform.wposition - s.transform.wposition).length);
	};

	scope(exit) Globals.resetForTests();
	Globals.simulators.start();
	Globals.simulators.join();

	trace("electra was ", minDist, " meters away from stork in electra_snake test");
	assert(s.dead);
}

*/

/*

unittest
{
	Globals.buildForTests();
	const TorpedoFactory tf = cast(TorpedoFactory) Globals.entityDb.getWeaponFactory("Minoga");
	WeaponParamValue[] pvs;
	WeaponParamValue pv;

	pv.type = WeaponParamType.course;
	pv.course = dgr2rad(0.0);
	pvs ~= pv;
	pv.type = WeaponParamType.activationRange;
	pv.range = 300.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.activeSpeed;
	pv.speed = 29.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.searchPattern;
	pv.searchPattern = WeaponSearchPattern.snake;
	pvs ~= pv;

	Torpedo t = tf.build(null, pvs);
	t.register();
	int imageCounter;
	cleanFolderForSonarImages("guidance", "minoga_headon");
	t.guidance.onSonarImageReady += (img, w, h) {
		writeTestImage("guidance", "minoga_headon", "minoga", img, w, h, imageCounter);
		imageCounter++;
	};

	SpawnReq req = SpawnReq("Stork", "Seven-blade screw");
	Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
	double mspd = speedForThrottle(s.rigidBody.hydroModel, cast(BasicPropulsor) s.propulsor);
	s.transform.position = vec2d(0, 2500);
	s.transform.rotation = dgr2rad(180);
	s.rigidBody.kinet.vel = courseVector(s.transform.rotation) * mspd;
	s.targetCourse = s.transform.rotation;
	s.targetThrottle = 0.1f;
	s.register();
	File* storkFile = writeRbodyCsvHeader("guidance", "minoga_headon", "stork");
	Globals.sim.onSimulationPassStart += captureVesselRbCsv(storkFile, s);

	File* minogaFile = writeRbodyCsvHeader("guidance", "minoga_headon", "minoga");
	Globals.sim.onSimulationPassStart += captureVesselRbCsv(minogaFile, t);
	Globals.sim.worldTimeLimit = 180 * cast(ulong)1e6;

	double minDist = double.max;
	Globals.sim.onSimulationPassStart += (now) {
		minDist = min(minDist, (t.transform.wposition - s.transform.wposition).length);
	};

	scope(exit) Globals.resetForTests();
	Globals.sim.start();
	Globals.sim.join();

	trace("minoga was ", minDist, " meters away from stork in minoga_headon test");
	assert(s.dead, "no detonation");
}

unittest
{
	Globals.buildForTests();
	const TorpedoFactory tf = cast(TorpedoFactory) Globals.entityDb.getWeaponFactory("Minoga");
	WeaponParamValue[] pvs;
	WeaponParamValue pv;

	pv.type = WeaponParamType.course;
	pv.course = dgr2rad(0.0);
	pvs ~= pv;
	pv.type = WeaponParamType.activationRange;
	pv.range = 400.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.activeSpeed;
	pv.speed = 21.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.marchSpeed;
	pv.speed = 21.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.searchPattern;
	pv.searchPattern = WeaponSearchPattern.straight;
	pvs ~= pv;

	Torpedo t = tf.build(null, pvs);
	t.register();
	int imageCounter;
	cleanFolderForSonarImages("guidance", "minoga_straight");
	t.guidance.onSonarImageReady += (img, w, h) {
		writeTestImage("guidance", "minoga_straight", "minoga", img, w, h, imageCounter);
		imageCounter++;
	};

	SpawnReq req = SpawnReq("Stork", "Seven-blade screw");
	Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
	double mspd = 0.4 * speedForThrottle(s.rigidBody.hydroModel, cast(BasicPropulsor) s.propulsor);
	s.transform.position = vec2d(-1300, 3000);
	s.transform.rotation = -dgr2rad(90);
	s.rigidBody.kinet.vel = courseVector(s.transform.rotation) * mspd;
	s.targetCourse = s.transform.rotation;
	s.targetThrottle = 0.4f;
	s.register();
	File* storkFile = writeRbodyCsvHeader("guidance", "minoga_straight", "stork");
	Globals.sim.onSimulationPassStart += captureVesselRbCsv(storkFile, s);

	File* minogaFile = writeRbodyCsvHeader("guidance", "minoga_straight", "minoga");
	Globals.sim.onSimulationPassStart += captureVesselRbCsv(minogaFile, t);
	Globals.sim.worldTimeLimit = 300 * cast(ulong)1e6;

	double minDist = double.max;
	Globals.sim.onSimulationPassStart += (now) {
		minDist = min(minDist, (t.transform.wposition - s.transform.wposition).length);
	};

	scope(exit) Globals.resetForTests();
	Globals.sim.start();
	Globals.sim.join();

	trace("minoga was ", minDist, " meters away from stork in minoga_straight test");
	assert(s.dead);
}


unittest
{
	Globals.buildForTests();
	const TorpedoFactory tf = cast(TorpedoFactory) Globals.entityDb.getWeaponFactory("Minoga");
	WeaponParamValue[] pvs;
	WeaponParamValue pv;

	pv.type = WeaponParamType.course;
	pv.course = dgr2rad(0.0);
	pvs ~= pv;
	pv.type = WeaponParamType.activationRange;
	pv.range = 400.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.activeSpeed;
	pv.speed = 29.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.marchSpeed;
	pv.speed = 29.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.searchPattern;
	pv.searchPattern = WeaponSearchPattern.straight;
	pvs ~= pv;

	Torpedo t = tf.build(null, pvs);
	t.register();
	int imageCounter;
	cleanFolderForSonarImages("guidance", "minoga_straight2");
	t.guidance.onSonarImageReady += (img, w, h) {
		writeTestImage("guidance", "minoga_straight2", "minoga", img, w, h, imageCounter);
		imageCounter++;
	};

	SpawnReq req = SpawnReq("Stork", "Seven-blade screw");
	Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
	double mspd = 0.9 * speedForThrottle(s.rigidBody.hydroModel, cast(BasicPropulsor) s.propulsor);
	s.transform.position = vec2d(-1500, 3000);
	s.transform.rotation = -dgr2rad(90);
	s.rigidBody.kinet.vel = courseVector(s.transform.rotation) * mspd;
	s.targetCourse = s.transform.rotation;
	s.targetThrottle = 0.9f;
	s.register();
	File* storkFile = writeRbodyCsvHeader("guidance", "minoga_straight2", "stork");
	Globals.sim.onSimulationPassStart += captureVesselRbCsv(storkFile, s);

	File* minogaFile = writeRbodyCsvHeader("guidance", "minoga_straight2", "minoga");
	Globals.sim.onSimulationPassStart += captureVesselRbCsv(minogaFile, t);
	Globals.sim.worldTimeLimit = 300 * cast(ulong)1e6;

	double minDist = double.max;
	Globals.sim.onSimulationPassStart += (now) {
		minDist = min(minDist, (t.transform.wposition - s.transform.wposition).length);
	};

	scope(exit) Globals.resetForTests();
	Globals.sim.start();
	Globals.sim.join();

	trace("minoga was ", minDist, " meters away from stork in minoga_straight2 test");
	assert(s.dead);
}


unittest
{
	Globals.buildForTests();
	const TorpedoFactory tf = cast(TorpedoFactory) Globals.entityDb.getWeaponFactory("Minoga");
	WeaponParamValue[] pvs;
	WeaponParamValue pv;

	pv.type = WeaponParamType.course;
	pv.course = dgr2rad(0.0);
	pvs ~= pv;
	pv.type = WeaponParamType.activationRange;
	pv.range = 400.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.activeSpeed;
	pv.speed = 29.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.marchSpeed;
	pv.speed = 29.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.searchPattern;
	pv.searchPattern = WeaponSearchPattern.straight;
	pvs ~= pv;

	Torpedo t = tf.build(null, pvs);
	t.register();
	int imageCounter;
	cleanFolderForSonarImages("guidance", "minoga_straight3");
	t.guidance.onSonarImageReady += (img, w, h) {
		writeTestImage("guidance", "minoga_straight3", "minoga", img, w, h, imageCounter);
		imageCounter++;
	};

	SpawnReq req = SpawnReq("Stork", "Seven-blade screw");
	Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
	double mspd = speedForThrottle(s.rigidBody.hydroModel, cast(BasicPropulsor) s.propulsor);
	s.transform.position = vec2d(300, 4000);
	s.transform.rotation = dgr2rad(180);
	s.rigidBody.kinet.vel = courseVector(s.transform.rotation) * mspd;
	s.targetCourse = s.transform.rotation;
	s.targetThrottle = 1.0f;
	s.register();
	File* storkFile = writeRbodyCsvHeader("guidance", "minoga_straight3", "stork");
	Globals.sim.onSimulationPassStart += captureVesselRbCsv(storkFile, s);

	File* minogaFile = writeRbodyCsvHeader("guidance", "minoga_straight3", "minoga");
	Globals.sim.onSimulationPassStart += captureVesselRbCsv(minogaFile, t);
	Globals.sim.worldTimeLimit = 300 * cast(ulong)1e6;

	double minDist = double.max;
	Globals.sim.onSimulationPassStart += (now) {
		minDist = min(minDist, (t.transform.wposition - s.transform.wposition).length);
	};

	scope(exit) Globals.resetForTests();
	Globals.sim.start();
	Globals.sim.join();

	trace("minoga was ", minDist, " meters away from stork in minoga_straight3 test");
	assert(s.dead);
}



unittest
{
	auto sim = Globals.buildForTests();
	const TorpedoFactory tf = cast(TorpedoFactory) Globals.entityDb.getWeaponFactory("Minoga");
	WeaponParamValue[] pvs;
	WeaponParamValue pv;

	pv.type = WeaponParamType.activationRange;
	pv.range = 450.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.activeSpeed;
	pv.speed = 29.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.marchSpeed;
	pv.speed = 29.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.searchPattern;
	pv.searchPattern = WeaponSearchPattern.spiral;
	pvs ~= pv;

	Torpedo t = tf.build(null, pvs);
	t.transform.rotation = dgr2rad(-20.0);
	t.register(sim);
	int imageCounter;
	cleanFolderForSonarImages("guidance", "minoga_spiral_stork");
	t.guidance.onSonarImageReady += (img, w, h) {
		writeTestImage("guidance", "minoga_spiral_stork", "minoga", img, w, h, imageCounter);
		imageCounter++;
	};

	SpawnReq req = SpawnReq("Stork", "Seven-blade screw");
	Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
	s.transform.position = vec2d(0.0, 0.0);
	s.transform.rotation = 0.0;
	s.rigidBody.kinet.vel = vec2d(0, 0);
	s.targetCourse = 0.0f;
	s.targetThrottle = 0.0f;
	s.register(sim);
	File* storkFile = writeRbodyCsvHeader("guidance", "minoga_spiral_stork", "stork");
	sim.onSimulationPassStart += captureVesselRbCsv(storkFile, s);

	File* minogaFile = writeRbodyCsvHeader("guidance", "minoga_spiral_stork", "minoga");
	sim.onSimulationPassStart += captureVesselRbCsv(minogaFile, t);
	sim.worldTimeLimit = 180 * cast(ulong)1e6;

	double minDist = double.max;
	sim.onSimulationPassStart += (sim, now) {
		if (t.guidance.activated)
			minDist = min(minDist, (t.transform.wposition - s.transform.wposition).length);
	};

	scope(exit) Globals.resetForTests();
	Globals.simulators.start();
	Globals.simulators.join();

	trace("minoga was ", minDist, " meters away from stork in minoga_spiral_stork test");
	assert(s.dead);
}




unittest
{
	Globals.buildForTests();
	const TorpedoFactory tf = cast(TorpedoFactory) Globals.entityDb.getWeaponFactory("Minoga");
	WeaponParamValue[] pvs;
	WeaponParamValue pv;

	pv.type = WeaponParamType.course;
	pv.course = dgr2rad(0.0);
	pvs ~= pv;
	pv.type = WeaponParamType.activationRange;
	pv.range = 400.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.searchPattern;
	pv.searchPattern = WeaponSearchPattern.spiral;
	pvs ~= pv;

	Torpedo t = tf.build(null, pvs);
	t.register();
	File* file = writeRbodyCsvHeader("guidance", "minoga_spiral", "minoga");
	Globals.sim.onSimulationPassStart += captureVesselRbCsv(file, t);
	Globals.sim.worldTimeLimit = 180 * cast(ulong)1e6;
	scope(exit) Globals.resetForTests();
	Globals.sim.start();
	Globals.sim.join();
}



unittest
{
	auto sim = Globals.buildForTests();
	const TorpedoFactory tf = cast(TorpedoFactory) Globals.entityDb.getWeaponFactory("Minoga");
	WeaponParamValue[] pvs;
	WeaponParamValue pv;

	pv.type = WeaponParamType.course;
	pv.course = dgr2rad(0.0);
	pvs ~= pv;
	pv.type = WeaponParamType.activationRange;
	pv.range = 400.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.activeSpeed;
	pv.speed = 25.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.searchPattern;
	pv.searchPattern = WeaponSearchPattern.snake;
	pvs ~= pv;
	pv.type = WeaponParamType.sensorMode;
	pv.sensorMode = WeaponSensorMode.passive;
	pvs ~= pv;

	Torpedo t = tf.build(null, pvs);
	t.register(sim);
	cleanFolderForSonarImages("guidance", "minoga_snake_passive");
	int imageRowCounter;
	ubyte[] imageData;
	t.guidance.onHydrophoneSliceReady += (const(ushort)[] bbData) {
		imageData ~= bbData.map!(
			s => (cast(float)s / ushort.max * ubyte.max).to!ubyte).array;
		imageRowCounter++;
	};

	SpawnReq req = SpawnReq("Stork", "Seven-blade screw");
	Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
	double mspd = speedForThrottle(s.rigidBody.hydroModel, cast(BasicPropulsor) s.propulsor);
	s.transform.position = vec2d(-2800, 3000);
	s.transform.rotation = -dgr2rad(90);
	s.rigidBody.kinet.vel = courseVector(s.transform.rotation) * mspd;
	s.targetCourse = s.transform.rotation;
	s.targetThrottle = 1.0f;
	s.register(sim);
	File* storkFile = writeRbodyCsvHeader("guidance", "minoga_snake_passive", "stork");
	sim.onSimulationPassStart += captureVesselRbCsv(storkFile, s);

	File* minogaFile = writeRbodyCsvHeader("guidance", "minoga_snake_passive", "minoga");
	sim.onSimulationPassStart += captureVesselRbCsv(minogaFile, t);
	sim.worldTimeLimit = 300 * cast(ulong)1e6;

	double minDist = double.max;
	sim.onSimulationPassStart += (simptr, now) {
		minDist = min(minDist, (t.transform.wposition - s.transform.wposition).length);
	};

	scope(exit) Globals.resetForTests();
	Globals.simulators.start();
	Globals.simulators.join();
	writeTestImage("guidance", "minoga_snake_passive", "minoga", imageData,
		(imageData.length / imageRowCounter).to!int, imageRowCounter, 0, "_hphone");
	trace("minoga was ", minDist,
		" meters away from stork in minoga_snake_passive test");
	assert(s.dead);
}

*/

/*


unittest
{
	auto sim = Globals.buildForTests();
	const TorpedoFactory tf = cast(TorpedoFactory) Globals.entityDb.getWeaponFactory("Electra");
	WeaponParamValue[] pvs;
	WeaponParamValue pv;

	pv.type = WeaponParamType.course;
	pv.course = dgr2rad(0.0);
	pvs ~= pv;
	pv.type = WeaponParamType.activationRange;
	pv.range = 400.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.activeSpeed;
	pv.speed = 25.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.searchPattern;
	pv.searchPattern = WeaponSearchPattern.snake;
	pvs ~= pv;
	pv.type = WeaponParamType.sensorMode;
	pv.sensorMode = WeaponSensorMode.passive;
	pvs ~= pv;

	Torpedo t = tf.build(null, pvs);
	t.register(sim);
	int imageRowCounter;
	ubyte[] imageData;
	t.guidance.onHydrophoneSliceReady += (const(ushort)[] bbData) {
		imageData ~= bbData.map!(
			s => (cast(float)s / ushort.max * ubyte.max).to!ubyte).array;
		imageRowCounter++;
	};

	SpawnReq req = SpawnReq("Stork", "Seven-blade screw");
	Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
	s.transform.position = vec2d(-2200, 3000);
	s.transform.rotation = -dgr2rad(90);
	s.rigidBody.kinet.vel = courseVector(s.transform.rotation) * 5.0f;
	s.targetCourse = s.transform.rotation;
	s.targetThrottle = 1.0f;
	s.register(sim);
	File* storkFile = writeRbodyCsvHeader("guidance", "electra_passive", "stork");
	sim.onSimulationPassStart += captureVesselRbCsv(storkFile, s);

	File* electraFile = writeRbodyCsvHeader("guidance", "electra_passive", "electra");
	sim.onSimulationPassStart += captureVesselRbCsv(electraFile, t);
	sim.worldTimeLimit = 300 * cast(ulong)1e6;

	double minDist = double.max;
	sim.onSimulationPassStart += (sim, now) {
		minDist = min(minDist, (t.transform.wposition - s.transform.wposition).length);
	};

	scope(exit) Globals.resetForTests();
	Globals.simulators.start();
	Globals.simulators.join();

	writeTestImage("guidance", "electra_passive", "electra", imageData,
		(imageData.length / imageRowCounter).to!int, imageRowCounter, 0, "_hphone");
	trace("electra was ", minDist, " meters away from stork in electra_passive test");
	assert(s.dead);
}

*/