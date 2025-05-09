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
module dsubs_server.tests.test_ai_sensors;

import std.stdio;

import dsubs_common.api.messages;
import dsubs_common.math;

import dsubs_server.common;
import dsubs_server.entitydb;
import dsubs_server.submarine;
import dsubs_server.propulsion;
import dsubs_server.ai.common;
import dsubs_server.ai.captain;
import dsubs_server.ai.acoustic;

import dsubs_server.tests.common;

/*

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

*/