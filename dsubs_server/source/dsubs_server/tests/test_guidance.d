module dsubs_server.tests.test_guidance;

import std.stdio;

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
	const TorpedoFactory tf = Globals.entityDb.getTorpedoFactory("Minoga");
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
	Globals.sim.start();
	Globals.sim.join();
	Globals.resetForTests();
}

unittest
{
	Globals.buildForTests();
	const TorpedoFactory tf = Globals.entityDb.getTorpedoFactory("Minoga");
	WeaponParamValue[] pvs;
	WeaponParamValue pv;

	// slow torp
	pv.type = WeaponParamType.marchCourse;
	pv.course = dgr2rad(-45.0f);
	pvs ~= pv;
	pv.type = WeaponParamType.marchSpeed;
	pv.speed = 20.0f;
	pvs ~= pv;
	pv.type = WeaponParamType.activationRange;
	pv.range = 5000.0f;
	pvs ~= pv;

	Torpedo t = tf.build(null, pvs);
	t.guidance.fuelLeft = 20.0f;
	t.transform.rotation = dgr2rad(-45.0f);
	t.register();
	File* file = writeRbodyCsvHeader("guidance", "minoga_endurance", "minoga20mps");
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
	Globals.sim.start();
	Globals.sim.join();
	Globals.resetForTests();
}

unittest
{
	Globals.buildForTests();
	const TorpedoFactory tf = Globals.entityDb.getTorpedoFactory("Minoga");
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
	t.guidance.onSonarImageReady += (img, w, h) {
		writeSonarImage("guidance", "minoga_snake", "minoga", img, w, h, imageCounter);
		imageCounter++;
	};
	// t.sonar.onmiImageCallback = (img, w, h) {
	// 	trace("omni image ready: ", img[0 .. 10]);
	// };

	Reflector[] reflectors;
	ReflectorPrototype refProto = ReflectorPrototype(
		vec2f(12.0f, 80.0f), [-25.0f, -19.0f, -10.0f]);
	for (int i = 0; i < 4; i++)
	{
		auto tansform = new Transform2D();
		tansform.position = vec2d(0, (i + 1) * 700);
		tansform.rotation = dgr2rad(90);
		reflectors ~= new Reflector(tansform, refProto);
	}
	foreach (r; reflectors)
		Globals.acous.registerReflector(r);

	File* file = writeRbodyCsvHeader("guidance", "minoga_snake", "minoga");
	Globals.sim.onSimulationPassStart += captureVesselRbCsv(file, t);
	Globals.sim.worldTimeLimit = 90 * cast(ulong)1e6;
	Globals.sim.start();
	Globals.sim.join();
	Globals.resetForTests();
}

unittest
{
	Globals.buildForTests();
	const TorpedoFactory tf = Globals.entityDb.getTorpedoFactory("Minoga");
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
	Globals.sim.start();
	Globals.sim.join();
	Globals.resetForTests();
}