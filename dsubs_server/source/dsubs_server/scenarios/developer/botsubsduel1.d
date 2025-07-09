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
module dsubs_server.scenarios.developer.botsubsduel1;

import std.algorithm;

import dsubs_common.api.messages;
import dsubs_common.api.entities;
import dsubs_common.math.angles;

import dsubs_server.common;
import dsubs_server.bots;
import dsubs_server.ai.captain;
import dsubs_server.player: SideOfConflict;
import dsubs_server.vessel;
import dsubs_server.submarine;
import dsubs_server.scenario;
import dsubs_server.scenarios.developer.developerscenario;
import dsubs_server.simulator;


final class BotSubsDuel1Dev: DeveloperScenario
{
	static AvailableScenarioConstants getConstants()
	{
		AvailableScenarioConstants constants;
		constants.name = "BotSubsDuel1";
		constants.shortDescription = "Duel of two medium Stork AIs";
		return constants;
	}

	this(Simulator sim)
	{
		super(sim);

		AICrew crew1 = new AICrew(BOT_DIFFICULTY.medium, "Screw Stork1");
		crew1.side = new SideOfConflict("Stork1 side");
		SpawnReq req1 = SpawnReq("Stork", "Seven-blade screw",
			[AmmoRoomFullState(0, [WeaponCount("Minoga", 12)]),
			AmmoRoomFullState(1, [WeaponCount("Decoy(active)", 10),
				WeaponCount("Decoy(passive)", 10)])],
			[TubeSpawnState(2, "Decoy(active)"), TubeSpawnState(3, "Decoy(passive)")]);
		Submarine botSub1 = Globals.entityDb.buildSubFromLoadout(req1, crew1);
		botSub1.transform.position = vec2d(2000.0, 2500.0);
		botSub1.transform.rotation = dgr2rad(90);
		m_simulator.bots.registerEntity(crew1);
		crew1.goal = new SwimToDestinationGoal(crew1, vec2d(-20000.0, 0.0));
		botSub1.register(m_simulator);

		SpawnReq req2 = SpawnReq("Stork", "Stork pumpjet",
			[AmmoRoomFullState(0, [WeaponCount("Minoga", 12)]),
			AmmoRoomFullState(1, [WeaponCount("Decoy(active)", 10),
				WeaponCount("Decoy(passive)", 10)])],
			[TubeSpawnState(2, "Decoy(active)"), TubeSpawnState(3, "Decoy(passive)")]);
		AICrew crew2 = new AICrew(BOT_DIFFICULTY.medium, "Pumpjet Stork2");
		crew2.side = new SideOfConflict("Stork2 side");
		Submarine botSub2 = Globals.entityDb.buildSubFromLoadout(req2, crew2);
		botSub2.transform.position = vec2d(-2000.0, 1500.0);
		botSub2.transform.rotation = dgr2rad(-90);
		m_simulator.bots.registerEntity(crew2);
		crew2.goal = new SwimToDestinationGoal(crew2, vec2d(20000.0, 1000.0));
		botSub2.register(m_simulator);
	}
}