module dsubs_server.tests.steering;

import std.stdio;
import std.file: mkdirRecurse;

import dsubs_common.api.protocols.backend;
import dsubs_common.math;

import dsubs_server.common;
import dsubs_server.entitydb;
import dsubs_server.submarine;
import dsubs_server.dynamics: RigidBody;


File writeRbodyCsvHeader(string testName, string entityName)
{
	mkdirRecurse("test_data/steering/");
	File f = File("test_data/steering/" ~ testName ~ "_" ~ entityName ~ ".csv", "w");
	f.writeln("world_time,pos_x,pos_y,dir_x,dir_y,vel_x,vel_y");
	return f;
}

void writeRbodyCsvRow(File file, usecs_t worldTime, RigidBody rb)
{
	vec2d rotVec = rb.kinet.forward * rb.kinet.velLength;
	file.writefln!"%d,%f,%f,%f,%f,%f,%f"(
		worldTime, rb.kinet.pos.x, rb.kinet.pos.y, rotVec.x, rotVec.y,
		rb.kinet.vel.x, rb.kinet.vel.y);
}

unittest
{
	File csvFile = writeRbodyCsvHeader("stork_turn", "stork");
	SpawnReq req = SpawnReq("Stork", "Five-blade screw");
	Globals.buildForTests();
	Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
	s.rigidBody.kinet.vel = vec2d(0, 16);
	s.targetThrottle = 1.0f;
	s.targetCourse = dgr2rad(-90);
	s.register();
	info("sub started at position ", s.transform.position);
	Globals.sim.worldTimeLimit = 40 * cast(ulong)1e6;
	Globals.sim.onSimulationPassStart += (usecs_t worldTime)
	{
		writeRbodyCsvRow(csvFile, worldTime, s.rigidBody);
	};
	Globals.sim.start();
	Globals.sim.join();
	info("sub finished at position ", s.transform.position);
	csvFile.close();
	Globals.resetForTests();
}