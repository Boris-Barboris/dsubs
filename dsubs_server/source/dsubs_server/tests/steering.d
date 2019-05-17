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

private auto captureCsv(File* f, Submarine s)
{
	return (usecs_t worldTime) { writeRbodyCsvRow(f, worldTime, s.rigidBody); };
}

unittest
{
	SpawnReq req = SpawnReq("Stork", "Five-blade screw");
	Globals.buildForTests();
	float[] throttles = [0.15f, 0.4f, 1.0f];
	foreach (float throttle; throttles)
	{
		Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
		s.rigidBody.kinet.vel = vec2d(0,
			maxSpeed(s.rigidBody.hydroModel, cast(BasicPropulsor) s.propulsor) *
			throttle);
		s.targetThrottle = throttle;
		s.targetCourse = dgr2rad(-90);
		s.register();
		File* file = writeRbodyCsvHeader("stork_turn",
			"stork" ~ throttle.to!string);
		Globals.sim.onSimulationPassStart += captureCsv(file, s);
	}
	Globals.sim.worldTimeLimit = 60 * cast(ulong)1e6;
	Globals.sim.start();
	Globals.sim.join();
	Globals.resetForTests();
}