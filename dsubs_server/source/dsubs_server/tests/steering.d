module dsubs_server.tests.steering;

import std.stdio;
import std.file: mkdirRecurse;

import dsubs_common.api.protocols.backend;
import dsubs_common.math;

import dsubs_server.common;
import dsubs_server.entitydb;
import dsubs_server.submarine;
import dsubs_server.propulsion;
import dsubs_server.dynamics: RigidBody;


File* writeRbodyCsvHeader(string testName, string entityName)
{
	mkdirRecurse("test_data/steering/");
	File* f = new File("test_data/steering/" ~ testName ~ "_" ~ entityName ~ ".csv", "w");
	f.writeln("world_time,pos_x,pos_y,dir_x,dir_y,vel_x,vel_y");
	return f;
}

void writeRbodyCsvRow(File* file, usecs_t worldTime, RigidBody rb)
{
	vec2d rotVec = rb.kinet.forward * rb.kinet.velLength;
	file.writefln!"%d,%f,%f,%f,%f,%f,%f"(
		worldTime, rb.kinet.pos.x, rb.kinet.pos.y, rotVec.x, rotVec.y,
		rb.kinet.vel.x, rb.kinet.vel.y);
}

private auto captureCsv(File* f, Submarine s, usecs_t shutdownOn = -1)
{
	return (usecs_t worldTime) {
		writeRbodyCsvRow(f, worldTime, s.rigidBody);
		if (worldTime == shutdownOn)
			s.shutdown();
	};
}

unittest
{
	SpawnReq req = SpawnReq("Stork", "Seven-blade screw");
	Globals.buildForTests();
	float[] throttles = [0.15f, 0.4f, 1.0f];
	foreach (float throttle; throttles)
	{
		Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
		s.transform.rotation = dgr2rad(-45);
		s.rigidBody.kinet.vel = throttle * courseVector(s.transform.rotation) *
			maxSpeed(s.rigidBody.hydroModel, cast(BasicPropulsor) s.propulsor);
		s.targetThrottle = throttle;
		s.targetCourse = dgr2rad(-90);
		s.register();
		File* file = writeRbodyCsvHeader("stork_speeds",
			"stork" ~ throttle.to!string);
		Globals.sim.onSimulationPassStart += captureCsv(
			file, s, (30 / throttle).to!usecs_t * 1000000);
	}
	Globals.sim.worldTimeLimit = 120 * cast(ulong)1e6;
	Globals.sim.start();
	Globals.sim.join();
	Globals.resetForTests();
}

unittest
{
	SpawnReq req = SpawnReq("Stork", "Seven-blade screw");
	Globals.buildForTests();
	Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
	s.rigidBody.kinet.vel = courseVector(0) *
		maxSpeed(s.rigidBody.hydroModel, cast(BasicPropulsor) s.propulsor);
	s.targetThrottle = 1.0f;
	s.targetCourse = dgr2rad(-179);
	s.register();
	File* file = writeRbodyCsvHeader("stork", "stork");
	Globals.sim.onSimulationPassStart += captureCsv(file, s);
	Globals.sim.worldTimeLimit = 30 * cast(ulong)1e6;
	Globals.sim.start();
	Globals.sim.join();
	Globals.resetForTests();
}