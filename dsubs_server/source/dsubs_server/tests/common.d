module dsubs_server.tests.common;

import std.stdio;
import std.file: mkdirRecurse;

import dsubs_common.api: usecs_t;
import dsubs_common.math;

import dsubs_server.common;
import dsubs_server.vessel: Vessel;
import dsubs_server.dynamics: RigidBody;


File* writeRbodyCsvHeader(string testGroup, string testName, string entityName)
{
	mkdirRecurse("test_data/" ~ testGroup);
	File* f = new File("test_data/" ~ testGroup ~ "/" ~ testName ~
		"_" ~ entityName ~ ".csv", "w");
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

auto captureVesselRbCsv(File* f, Vessel s, usecs_t shutdownOn = -1)
{
	return (usecs_t worldTime) {
		writeRbodyCsvRow(f, worldTime, s.rigidBody);
		if (worldTime == shutdownOn)
			s.shutdown();
	};
}