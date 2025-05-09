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
module dsubs_server.tests.test_steering;

import std.stdio;

import dsubs_common.api.messages;
import dsubs_common.math;

import dsubs_server.common;
import dsubs_server.entitydb;
import dsubs_server.submarine;
import dsubs_server.propulsion;

import dsubs_server.tests.common;


/*

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
			speedForThrottle(s.rigidBody.hydroModel, cast(BasicPropulsor) s.propulsor);
		s.targetThrottle = throttle;
		s.targetCourse = dgr2rad(-90);
		s.register();
		File* file = writeRbodyCsvHeader("steering", "stork_speeds",
			"stork" ~ throttle.to!string);
		Globals.sim.onSimulationPassStart += captureVesselRbCsv(
			file, s, (30 / throttle).to!usecs_t * 1000000);
	}
	Globals.sim.worldTimeLimit = 120 * cast(ulong)1e6;
	scope(exit) Globals.resetForTests();
	Globals.sim.start();
	Globals.sim.join();
}

unittest
{
	SpawnReq req = SpawnReq("Stork", "Seven-blade screw");
	Globals.buildForTests();
	Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
	double mspd = speedForThrottle(s.rigidBody.hydroModel, cast(BasicPropulsor) s.propulsor);
	trace("max stork speed: ", mspd);
	s.rigidBody.kinet.vel = courseVector(0) * mspd;
	s.targetThrottle = 1.0f;
	s.targetCourse = dgr2rad(-179);
	s.register();
	File* file = writeRbodyCsvHeader("steering", "stork_turn", "stork");
	Globals.sim.onSimulationPassStart += captureVesselRbCsv(file, s);
	Globals.sim.worldTimeLimit = 45 * cast(ulong)1e6;
	scope(exit) Globals.resetForTests();
	Globals.sim.start();
	Globals.sim.join();
}

unittest
{
	SpawnReq req = SpawnReq("Stork", "Seven-blade screw");
	Globals.buildForTests();
	Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
	s.targetThrottle = 1.0f;
	s.targetCourse = dgr2rad(0);
	s.register();
	File* file = writeRbodyCsvHeader("steering", "stork_accel", "stork");
	Globals.sim.onSimulationPassStart += captureVesselRbCsv(file, s);
	Globals.sim.worldTimeLimit = 60 * cast(ulong)1e6;
	scope(exit) Globals.resetForTests();
	Globals.sim.start();
	Globals.sim.join();
}


unittest
{
	SpawnReq req = SpawnReq("Lima", "Five-blade Lima screw");
	Globals.buildForTests();
	Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
	double mspd = speedForThrottle(s.rigidBody.hydroModel, cast(BasicPropulsor) s.propulsor);
	trace("max Lima speed: ", mspd);
	s.rigidBody.kinet.vel = courseVector(0) * mspd;
	s.targetThrottle = 1.0f;
	s.targetCourse = dgr2rad(-179.99);
	s.register();
	File* file = writeRbodyCsvHeader("steering", "lima_turn", "lima");
	Globals.sim.onSimulationPassStart += captureVesselRbCsv(file, s);
	Globals.sim.worldTimeLimit = 45 * cast(ulong)1e6;
	scope(exit) Globals.resetForTests();
	Globals.sim.start();
	Globals.sim.join();
}

unittest
{
	SpawnReq req = SpawnReq("Stork", "Seven-blade screw");
	Globals.buildForTests();
	Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
	s.targetThrottle = 0.4f;
	s.targetCourse = -dgr2rad(30);
	s.rigidBody.wires[0].desiredLength = 600.0f;
	s.register();
	File* file = writeRbodyCsvHeader("steering", "towed_wire", "stork");
	Globals.sim.onSimulationPassStart += captureVesselRbCsv(file, s);
	File* fileWire = writeRbodyCsvHeader("steering", "towed_wire", "wire_tail");
	Globals.sim.onSimulationPassStart += (usecs_t worldTime) {
		if (Globals.sim.worldTime > 120 * cast(ulong)1e6)
			s.targetCourse = dgr2rad(90);
		writeWireCsvRow(fileWire, worldTime, s.rigidBody.wires[0]);
	};
	Globals.sim.worldTimeLimit = 900 * cast(ulong)1e6;
	scope(exit) Globals.resetForTests();
	Globals.sim.start();
	Globals.sim.join();
}

*/