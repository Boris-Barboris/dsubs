module dsubs_server.tests.test_ai_navigation;

import std.stdio;

import dsubs_common.api.protocols.backend;
import dsubs_common.math;

import dsubs_server.common;
import dsubs_server.entitydb;
import dsubs_server.submarine;
import dsubs_server.propulsion;
import dsubs_server.ai.captain;

import dsubs_server.tests.common;



unittest
{
	SpawnReq req = SpawnReq("Stork", "Seven-blade screw");
	Globals.buildForTests();
	AICrew crew = new AICrew(BOT_DIFFICULTY.easy);
	Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
	crew.submarine = s;
	s.captain = crew;
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