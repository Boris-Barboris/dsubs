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
module dsubs_server.scenarios.developer.developerscenario;

import std.algorithm;

import dsubs_common.api.messages;
import dsubs_common.api.entities;
import dsubs_common.math.angles;

import dsubs_server.common;
import dsubs_server.vessel;
import dsubs_server.player;
import dsubs_server.submarine;
import dsubs_server.scenario;
import dsubs_server.simulator;


class DeveloperScenario: Scenario
{
	this(Simulator sim)
	{
		super(sim);
		sim.canBePaused = true;
		sim.runWithoutPlayers = true;
	}

	override void onBeforeSimulation() {}

	override ShouldSimTerminate onAfterSimulation(usecs_t simTimePassed)
	{
		return ShouldSimTerminate.no;
	}

	override void selectPlayerSpawnPosition(Player player,
		out vec2d position, out double rotation)
	{
		position = vec2d(0, 0);
		rotation = 0;
	}

	override void generateBriefing(Player player, out MapElement[] mapElements,
		out ScenarioGoal[] goals, out ChatMessage briefing) {}
}