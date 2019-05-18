module dsubs_server.tests.test_guidance;

import std.stdio;

import dsubs_common.api.protocols.backend;
import dsubs_common.math;

import dsubs_server.common;
import dsubs_server.entitydb;
import dsubs_server.submarine;
import dsubs_server.propulsion;
import dsubs_server.torpedo;

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
	File* file = writeRbodyCsvHeader("guidance", "minoga", "minoga");
	Globals.sim.onSimulationPassStart += captureCsv(file, t);
	Globals.sim.worldTimeLimit = 40 * cast(ulong)1e6;
	Globals.sim.start();
	Globals.sim.join();
	Globals.resetForTests();
}