module dsubs_server.tests.test_guidance;

import std.stdio;
import std.algorithm: min;

import dsubs_common.api.protocols.backend;
import dsubs_common.math;

import dsubs_server.common;
import dsubs_server.entitydb;
import dsubs_server.submarine;
import dsubs_server.propulsion;
import dsubs_server.torpedo;
import dsubs_sound.activesonar;

import dsubs_server.tests.common;


unittest
{
	Globals.buildForTests();
	const TorpedoFactory tf = cast(TorpedoFactory) Globals.entityDb.getWeaponFactory("Minoga");
	WeaponParamValue[] pvs;
	WeaponParamValue pv;

	pv.type = WeaponParamType.marchCourse;
	pv.course = dgr2rad(-90.0);
	pvs ~= pv;
	pv.type = WeaponParamType.activeCourse;
	pv.course = dgr2rad(0.0);
	pvs ~= pv;
	pv.type = WeaponParamType.activationRange;
	pv.range = 400.0f;
	pvs ~= pv;


	Torpedo t = tf.build(null, pvs);
	t.register();
	File* file = writeRbodyCsvHeader("guidance", "minoga_turning", "minoga");
	Globals.sim.onSimulationPassStart += captureVesselRbCsv(file, t);
	Globals.sim.worldTimeLimit = 40 * cast(ulong)1e6;
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

	// slow torp
	pv.type = WeaponParamType.marchCourse;
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
	pv.type = WeaponParamType.marchCourse;
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

	pv.type = WeaponParamType.marchCourse;
	pv.course = dgr2rad(0.0);
	pvs ~= pv;
	pv.type = WeaponParamType.activeCourse;
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
		writeSonarImage("guidance", "minoga_snake", "minoga", img, w, h, imageCounter);
		imageCounter++;
	};

	SpawnReq req = SpawnReq("Stork", "Seven-blade screw");
	Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
	double mspd = maxSpeed(s.rigidBody.hydroModel, cast(BasicPropulsor) s.propulsor);
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

unittest
{
	Globals.buildForTests();
	const TorpedoFactory tf = cast(TorpedoFactory) Globals.entityDb.getWeaponFactory("Minoga");
	WeaponParamValue[] pvs;
	WeaponParamValue pv;

	pv.type = WeaponParamType.marchCourse;
	pv.course = dgr2rad(0.0);
	pvs ~= pv;
	pv.type = WeaponParamType.activeCourse;
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
		writeSonarImage("guidance", "minoga_headon", "minoga", img, w, h, imageCounter);
		imageCounter++;
	};

	SpawnReq req = SpawnReq("Stork", "Seven-blade screw");
	Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
	double mspd = maxSpeed(s.rigidBody.hydroModel, cast(BasicPropulsor) s.propulsor);
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

	pv.type = WeaponParamType.marchCourse;
	pv.course = dgr2rad(0.0);
	pvs ~= pv;
	pv.type = WeaponParamType.activeCourse;
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
		writeSonarImage("guidance", "minoga_straight", "minoga", img, w, h, imageCounter);
		imageCounter++;
	};

	SpawnReq req = SpawnReq("Stork", "Seven-blade screw");
	Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
	double mspd = 0.4 * maxSpeed(s.rigidBody.hydroModel, cast(BasicPropulsor) s.propulsor);
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

	pv.type = WeaponParamType.marchCourse;
	pv.course = dgr2rad(0.0);
	pvs ~= pv;
	pv.type = WeaponParamType.activeCourse;
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