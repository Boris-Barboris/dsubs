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
module dsubs_server.tests.test_ai_navigation;

import std.stdio;

import dsubs_common.api.messages;
import dsubs_common.math;

import dsubs_server.common;
import dsubs_server.entitydb;
import dsubs_server.submarine;
import dsubs_server.propulsion;
import dsubs_server.ai.aicaptain;

import dsubs_server.tests.common;

/*

unittest
{
	SpawnReq req = SpawnReq("Stork", "Seven-blade screw");
	Globals.buildForTests();
	AICrew crew = new AICrew(BOT_DIFFICULTY.medium);
	Submarine s = Globals.entityDb.buildSubFromLoadout(req, crew);
	s.register();
	SwimToDestinationGoal goal1, goal2;
	goal1 = new SwimToDestinationGoal(crew, vec2d(-1000, 0));
	goal2 = new SwimToDestinationGoal(crew, vec2d(-1000, 500));
	crew.goal = goal1;
	Globals.bots.registerEntity(crew);
	File* file = writeRbodyCsvHeader("ai_navigation", "swim_to_dest", "stork");
	Globals.sim.onSimulationPassStart += captureVesselRbCsv(file, s);
	Globals.sim.onSimulationPassEnd += (usecs_t dt) {
		if (crew.goal.status == GoalStatus.succeeded && crew.goal is goal1)
			crew.goal = goal2;
		if (goal2.status == GoalStatus.succeeded)
			Globals.sim.stop();
	};
	Globals.sim.worldTimeLimit = 600 * cast(ulong)1e6;
	scope(exit) Globals.resetForTests();
	Globals.sim.start();
	Globals.sim.join();
	assert(crew.goal.status == GoalStatus.succeeded);
	assert(goal2 is crew.goal);
}
*/