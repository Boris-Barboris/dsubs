/*
DSubs
Copyright (C) 2017-2025 Baranin Alexander

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
module dsubs_server.tests.common;

import std.stdio;
import std.file;

import imageformats: write_image, ColFmt;

import dsubs_common.api: usecs_t;
import dsubs_common.math;

import dsubs_server.common;
import dsubs_server.vessel: Vessel;
import dsubs_server.simulator: Simulator;
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
	return (Simulator sim, usecs_t worldTime) {
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

void writeTestImage(string testGroup, string testName, string entityName,
	const(ubyte)[] rawBytes, int w, int h, int imageIndex, string suffix = "_sonar")
{
	string dirName = "test_data/" ~ testGroup ~ "/" ~ testName ~ "_images";
	mkdirRecurse(dirName);
	string fileName = entityName ~ suffix ~ imageIndex.to!string ~ ".png";
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
	void initialize(Simulator sim)
	{
		try
		{
			rmdirRecurse("test_data/" ~ testGroup);
		}
		catch(Exception) {}
		initialized = true;
		sim.onSimulationPassStart += &callback;
	}

	void callback(Simulator sim, usecs_t worldTime)
	{
		foreach (Vessel v; sim.vessels.entities)
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