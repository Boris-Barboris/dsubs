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
module dsubs_server.tests.test_ai_duel;

import std.stdio;

import dsubs_common.api.messages;
import dsubs_common.math;

import dsubs_server.common;
import dsubs_server.entitydb;
import dsubs_server.submarine;
import dsubs_server.propulsion;
import dsubs_server.player: SideOfConflict;
import dsubs_server.ai.common;
import dsubs_server.ai.captain;
import dsubs_server.ai.acoustic;

import dsubs_server.tests.common;


/*

unittest
{
	info("ai_easy_duel_test");
	SpawnReq req1 = SpawnReq("Stork", "Seven-blade screw",
			[AmmoRoomFullState(0, [WeaponCount("Minoga", 10)]),
			AmmoRoomFullState(1, [WeaponCount("Decoy(active)", 10),
				WeaponCount("Decoy(passive)", 10)])],
			[TubeSpawnState(2, "Decoy(active)"), TubeSpawnState(3, "Decoy(passive)")]);
	SpawnReq req2 = SpawnReq("Lima", "Five-blade Lima screw",
			[AmmoRoomFullState(0, [WeaponCount("Minoga", 10)]),
			AmmoRoomFullState(1, [WeaponCount("Decoy(active)", 10),
				WeaponCount("Decoy(passive)", 10)])],
			[TubeSpawnState(2, "Decoy(active)"), TubeSpawnState(3, "Decoy(passive)")]);
	auto sim = Globals.buildForTests();
	AICrew boat1Crew = new AICrew(BOT_DIFFICULTY.easy);
	boat1Crew.side = new SideOfConflict("boat1 side");
	AICrew boat2Crew = new AICrew(BOT_DIFFICULTY.easy);
	boat2Crew.side = new SideOfConflict("boat2 side");
	Submarine boat1 = Globals.entityDb.buildSubFromLoadout(req1, boat1Crew);
	Submarine boat2 = Globals.entityDb.buildSubFromLoadout(req2, boat2Crew);
	boat1.register(sim);
	boat2.transform.position = vec2d(-3500, 3500);
	boat2.register(sim);
	boat1Crew.goal = new SwimToDestinationGoal(boat1Crew, vec2d(-1500, 5000));
	boat2Crew.goal = new SwimToDestinationGoal(boat2Crew, vec2d(0, 0));
	sim.bots.registerEntity(boat1Crew);
	sim.bots.registerEntity(boat2Crew);
	AllVesselCvsWriter writer = AllVesselCvsWriter("ai_duel", "easy_duel");
	writer.initialize(sim);
	sim.worldTimeLimit = 900 * cast(ulong)1e6;
	scope(exit) Globals.resetForTests();
	Globals.simulators.start();
	Globals.simulators.join();
}



*/


unittest
{
	info("ai_medium_duel_test");
	SpawnReq req1 = SpawnReq("Stork", "Seven-blade screw",
			[AmmoRoomFullState(0, [WeaponCount("Minoga", 10)]),
			AmmoRoomFullState(1, [WeaponCount("Decoy(active)", 10),
				WeaponCount("Decoy(passive)", 10)])],
			[TubeSpawnState(2, "Decoy(active)"), TubeSpawnState(3, "Decoy(passive)")]);
	SpawnReq req2 = SpawnReq("Lima", "Five-blade Lima screw",
			[AmmoRoomFullState(0, [WeaponCount("Electra", 10)]),
			AmmoRoomFullState(1, [WeaponCount("Decoy(active)", 10),
				WeaponCount("Decoy(passive)", 10)])],
			[TubeSpawnState(2, "Decoy(active)"), TubeSpawnState(3, "Decoy(passive)")]);
	auto sim = Globals.buildForTests();
	AICrew boat1Crew = new AICrew(BOT_DIFFICULTY.medium);
	boat1Crew.side = new SideOfConflict("boat1 side");
	AICrew boat2Crew = new AICrew(BOT_DIFFICULTY.medium);
	boat2Crew.side = new SideOfConflict("boat2 side");
	Submarine boat1 = Globals.entityDb.buildSubFromLoadout(req1, boat1Crew);
	Submarine boat2 = Globals.entityDb.buildSubFromLoadout(req2, boat2Crew);
	boat1.register(sim);
	boat2.transform.position = vec2d(-3500, 3500);
	boat2.register(sim);
	boat1Crew.goal = new SwimToDestinationGoal(boat1Crew, vec2d(-1500, 5000));
	boat2Crew.goal = new SwimToDestinationGoal(boat2Crew, vec2d(-3000, 0));
	sim.bots.registerEntity(boat1Crew);
	sim.bots.registerEntity(boat2Crew);
	AllVesselCvsWriter writer = AllVesselCvsWriter("ai_duel", "medium_duel");
	writer.initialize(sim);
	sim.worldTimeLimit = 900 * cast(ulong)1e6;
	scope(exit) Globals.resetForTests();
	Globals.simulators.start();
	Globals.simulators.join();
}
