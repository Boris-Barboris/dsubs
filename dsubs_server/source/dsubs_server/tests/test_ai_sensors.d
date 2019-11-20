module dsubs_server.tests.test_ai_sensors;

import std.stdio;

import dsubs_common.api.protocols.backend;
import dsubs_common.math;

import dsubs_server.common;
import dsubs_server.entitydb;
import dsubs_server.submarine;
import dsubs_server.propulsion;
import dsubs_server.ai.common;
import dsubs_server.ai.captain;
import dsubs_server.ai.acoustic;

import dsubs_server.tests.common;


unittest
{
	info("ai_acoustic_test");
	SpawnReq req = SpawnReq("Stork", "Seven-blade screw");
	Globals.buildForTests();
	AICrew listenerCrew = new AICrew(BOT_DIFFICULTY.easy);
	AICrew swimmerCrew = new AICrew(BOT_DIFFICULTY.easy);
	Submarine listener = Globals.entityDb.buildSubFromLoadout(req, listenerCrew);
	Submarine swimmer = Globals.entityDb.buildSubFromLoadout(req, swimmerCrew);
	listener.register();
	swimmer.transform.position = vec2d(-3000, 1000);
	swimmer.register();
	SwimToDestinationGoal goal1;
	goal1 = new SwimToDestinationGoal(swimmerCrew, vec2d(-3000, -1000));
	swimmerCrew.goal = goal1;
	Globals.bots.registerEntity(swimmerCrew);
	Globals.bots.registerEntity(listenerCrew);
	Globals.sim.onSimulationPassEnd += (usecs_t dt) {
		if (goal1.status == GoalStatus.succeeded)
			Globals.sim.stop();
		if (Globals.sim.worldTime > 30_000_000)
		{
			auto ctc = listenerCrew.state.contacts[swimmer];
			// trace(*ctc);
		}
		if (Globals.sim.worldTime > 90_000_000)
		{
			Contact* ctc = listenerCrew.state.contacts[swimmer];
			assert(ctc.classification == ContactClass.submarine);
			assert(ctc.passiveSonarPoints >= 0.0f);
		}
	};
	Globals.sim.worldTimeLimit = 150 * cast(ulong)1e6;
	scope(exit) Globals.resetForTests();
	Globals.sim.start();
	Globals.sim.join();
}