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
module dsubs_server.scenarios.tutorials.torpedotutorial;

import std.algorithm;

import dsubs_common.api.messages;
import dsubs_common.api.entities;
import dsubs_common.math.angles;

import dsubs_server.common;
import dsubs_server.bots;
import dsubs_server.ai.aicaptain;
import dsubs_server.vessel;
import dsubs_server.submarine;
import dsubs_server.scenario;
import dsubs_server.simulator;


final class TorpedoTutorial: SinglePlayerScenario
{
	static AvailableScenarioConstants getConstants()
	{
		AvailableScenarioConstants constants;
		constants.name = "Torpedoes";
		constants.shortDescription = "Learn to use guided torpedoes.";
		constants.fullDescription =
`Submarines are armed with self-propelled torpedoes of verious range, speed and intelligence. This tutorial teaches the basics of torpedo reloading, aiming and firing.`;
		constants.allowedEntities = EntityDbShort(
			["Lima"], ["Five-blade Lima screw"], ["Electra"]);
		return constants;
	}

	this(Simulator sim)
	{
		super(sim, ChatMessage(longUnixTime(), ChatMessageType.scenarioNotice,
			"Welcome to torpedo tutorial"));
		m_victoryLongReport =
		`You are now capable of destroying enemy ships.`;

		SimpleGoal killTargetGoal = new SimpleGoal("Kill the target",
`Detect the target using active sonar (see previous tutorial). Aim and kill ` ~
`it.`);
		addVisibleGoal(killTargetGoal);

		AICrew crew = new AICrew(BOT_DIFFICULTY.easy);
		SpawnReq req = SpawnReq("Bot trader", "Civilian three-blade screw");
		Submarine botSub = Globals.entityDb.buildSubFromLoadout(req, crew);
		botSub.transform.position = vec2d(2000.0, 2500.0);
		botSub.transform.rotation = dgr2rad(90);
		m_simulator.bots.registerEntity(crew);
		crew.goal = new SwimToDestinationGoal(crew, vec2d(-20000.0, 0.0));
		botSub.register(m_simulator);

		ScenarioTrigger killTrigger = new ScenarioTrigger(
			new DeadCondition({ return botSub; }),
			{ killTargetGoal.markSuccess(); },
			true, 10_000_000L);
		addTrigger(killTrigger);

		// text hints
		m_syncState.mapElements.addElement("zoomhint",
			MapElement.text(MapText(
				vec2d(10, 10), 16), COLOR_HINT,
				"zoom out for hints"));
		m_syncState.mapElements.addElement("torphint",
			MapElement.text(MapText(
				vec2d(400, 500), 14), COLOR_HINT,
`In the bottom left corner of tactical screen you can see 4 tube
control panels. On Lima-class submarine tubes 1, 2 are dedicated
to bow torpedo tubes and 3, 4 to decoy tubes. Start loading torpedo
tubes with 'Electra' torpedo by clicking on the 'empty' button and
selecting 'Electra'. Loading will take around 1 minute. In the
meantime, you should detect and perform TMA on the test target.
Recollect the lessons of previous 'Active sonar, TMA' tutorial.

When the torpedo is loaded in the tube, 'Aim' buttons become active.
Press the 'Aim' button above tube 1. This activates aiming
controls. These controls are:
  course - torpedo will run on this course before starting it's search.
  RTE(m) - Run To Enable distance. Once the torpedo has covered this
	distance it activates it's sensors and the search pattern.
  RTE spd - speed before reaching RTE. Slower torpedoes run longer
	and cover larger distances.
  ACT spd - speed on the search pattern. Slower torpedoes suffer less
	noise interference and can detect stealthier targets.
  ptrn - search pattern.
  sens - sensor type. Active sensor uses active sonar. Passive
	sensor looks for target's noise. It is recommended to reduce
	ACT spd to <25 m/s in this sensor mode.

Course and RTE(m) are two most important parameters. It is better
to edit them by dragging the '1' pictogram on a tactical map.
Orange trajectory section is an estimate of torpedo's path before
activation. Red section is a search pattern.

In order to account for solution's movement you need to lead your aim.
Enter TMA mode again by clicking on your target.
If you have set the solution's velocity, cyan line will appear
between the solution and torpedo trajectory. This line is the
shortest distance the target and your torpedo will ever be between
each other. Try to aim in such a way that the cyal line is short and
the target is 300-400m forward from the torpedo at the point of
it's sensor activation (red trajectory section start).

Once the tubes are loaded, you can change the desired tube state:
  D - dry state. In this state tubes can be reloaded.
  F - flooded state. This is a transient state in which tube internals
	are depressurized. Flooding and drying up the tube is a noisy
	process.
  O - open state. Tube is ready to fire the torpedo.

Once you're satisfied with your aim, click the 'O' button of
the tube to open it. Once the tube is open, the 'Launch' button
becomes active. Press it.

You can follow the torpedo path on your active sonar.
Good luck!`));
	}
}