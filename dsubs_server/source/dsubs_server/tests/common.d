module dsubs_server.tests.common;

import std.stdio;
import std.file;

import imageformats: write_image, ColFmt;

import dsubs_common.api: usecs_t;
import dsubs_common.math;

import dsubs_server.common;
import dsubs_server.vessel: Vessel;
import dsubs_server.dynamics: RigidBody, WirePoint, AttachedWire;


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

void writeWireCsvRow(File* file, usecs_t worldTime, AttachedWire aw)
{
	if (aw.sensorTransformValid)
	{
		vec2d rotVec = aw.sensorPointVel;
		file.writefln!"%d,%f,%f,%f,%f,%f,%f"(
			worldTime, aw.sensorTransform.wposition.x, aw.sensorTransform.wposition.y,
			rotVec.x, rotVec.y, rotVec.x, rotVec.y);
	}
}

auto captureVesselRbCsv(File* f, Vessel s, usecs_t shutdownOn = -1)
{
	return (usecs_t worldTime) {
		writeRbodyCsvRow(f, worldTime, s.rigidBody);
		if (worldTime == shutdownOn)
			s.shutdown();
	};
}

void cleanFolderForSonarImages(string testGroup, string testName)
{
	string dirName = "test_data/" ~ testGroup ~ "/" ~ testName ~ "_images";
	try
	{
		rmdirRecurse(dirName);
	}
	catch (Exception fileEx) {}
}

void writeSonarImage(string testGroup, string testName, string entityName,
	const(ubyte)[] rawBytes, int w, int h, int imageIndex)
{
	string dirName = "test_data/" ~ testGroup ~ "/" ~ testName ~ "_images";
	mkdirRecurse(dirName);
	string fileName = entityName ~ "_sonar" ~ imageIndex.to!string ~ ".png";
	write_image(dirName ~ "/" ~ fileName, w, h, rawBytes, ColFmt.Y);
}


/// Writes csv files for all vessels
struct AllVesselCvsWriter
{
	private bool initialized;
	string testGroup, testName;
	File*[Vessel] vesselFileMap;
	int[string] vesselIndeces;

	this(string testGroup, string testName)
	{
		this.testGroup = testGroup;
		this.testName = testName;
	}

	~this()
	{
		if (initialized)
		{
			foreach (File* file; vesselFileMap.byValue)
				file.detach();
		}
	}

	/// WARNING: this cleans the directory
	void initialize()
	{
		try
		{
			rmdirRecurse("test_data/" ~ testGroup);
		}
		catch(Exception) {}
		initialized = true;
		Globals.sim.onSimulationPassStart += &callback;
	}

	void callback(usecs_t worldTime)
	{
		foreach (Vessel v; Globals.vessels.entities)
		{
			if (v.dead)
				continue;
			File* file;
			if (v !in vesselFileMap)
			{
				int index = vesselIndeces.get(v.prototypeName, 0);
				index++;
				vesselIndeces[v.prototypeName] = index;
				file = writeRbodyCsvHeader(testGroup, testName,
					v.prototypeName() ~ index.to!string);
				vesselFileMap[v] = file;
			}
			else
				file = vesselFileMap[v];
			writeRbodyCsvRow(file, worldTime, v.rigidBody);
		}
	}
}