module dsubs_server.tests.test_ai_duel;

import std.stdio;

import dsubs_common.api.protocols.backend;
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


unittest
{
	info("ai_easy_duel_test");
	SpawnReq req = SpawnReq("Stork", "Seven-blade screw",
			[AmmoRoomFullState(0, [WeaponCount("Minoga", 8)])]);
	Globals.buildForTests();
	AICrew boat1Crew = new AICrew(BOT_DIFFICULTY.easy);
	boat1Crew.side = new SideOfConflict("boat1 side");
	AICrew boat2Crew = new AICrew(BOT_DIFFICULTY.easy);
	boat2Crew.side = new SideOfConflict("boat2 side");
	Submarine boat1 = Globals.entityDb.buildSubFromLoadout(req, boat1Crew);
	Submarine boat2 = Globals.entityDb.buildSubFromLoadout(req, boat2Crew);
	boat1.register();
	boat2.transform.position = vec2d(-2000, 1000);
	boat2.register();
	SwimToDestinationGoal goal1;
	goal1 = new SwimToDestinationGoal(boat2Crew, vec2d(-3000, -1000));
	boat2Crew.goal = goal1;
	Globals.bots.registerEntity(boat2Crew);
	Globals.bots.registerEntity(boat1Crew);
	AllVesselCvsWriter writer = AllVesselCvsWriter("ai_duel", "easy_duel");
	writer.initialize();
	Globals.sim.worldTimeLimit = 600 * cast(ulong)1e6;
	scope(exit) Globals.resetForTests();
	Globals.sim.start();
	Globals.sim.join();
}