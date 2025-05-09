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
module dsubs_server.scenarios.tutorials.sonartutorial;

import std.algorithm;

import dsubs_common.api.messages;
import dsubs_common.api.entities;
import dsubs_common.math.angles;

import dsubs_server.common;
import dsubs_server.bots;
import dsubs_server.ai.captain;
import dsubs_server.vessel;
import dsubs_server.submarine;
import dsubs_server.scenario;
import dsubs_server.simulator;


final class ActiveSonarTutorial: SinglePlayerScenario
{
	static AvailableScenarioConstants getConstants()
	{
		AvailableScenarioConstants constants;
		constants.name = "Active sonar, TMA";
		constants.shortDescription = "Learn to use active sonar and basics of TMA.";
		constants.fullDescription =
`Active sonar is a powerful sound transmitter/receiver that is used to locate distant objects by illuminating them and listening to the echo. It gives reasonably precise positional data, but is very loud, making the enemy aware of your identity and approximate position.

Target Motion Analysis (TMA) is a process of estimating target position and velocity from the set of imprecise historical sensor measurements. It is required to produce accurate information to torpedoes, because their travel time is very long and requires a good lead on the target.

This tutorial provides a simple cruising civilian to experiment on. Victory is achieved by shadowing the target very closely for 1 minute to prove that your TMA was on point.`;
		constants.allowedEntities = EntityDbShort(["Stork"], ["Seven-blade screw"]);
		return constants;
	}

	this(Simulator sim)
	{
		super(sim, ChatMessage(longUnixTime(), ChatMessageType.scenarioNotice,
			"Welcome to active sonar tutorial"));
		m_victoryLongReport =
		`You now know how to ping and use sonar information to build a solution.`;

		SimpleGoal shadowGoal = new SimpleGoal("Shadow the target for 1 minute",
`Detect the target using active sonar. Generate sonar samples, create solution, stay at most 100m away from the target for 1 minute.`);
		addVisibleGoal(shadowGoal);

		AICrew crew = new AICrew(BOT_DIFFICULTY.easy);
		SpawnReq req = SpawnReq("Bot trader", "Civilian three-blade screw");
		Submarine botSub = Globals.entityDb.buildSubFromLoadout(req, crew);
		botSub.transform.position = vec2d(1500.0, 500.0);
		botSub.transform.rotation = dgr2rad(90);
		m_simulator.bots.registerEntity(crew);
		crew.goal = new SwimToDestinationGoal(crew, vec2d(-20000.0, 4000.0));
		botSub.register(m_simulator);

		ScenarioTrigger shadowTrigger = new ScenarioTrigger(
			new DistanceCondition(
				{ return m_playerSub.transform; },
				{ return botSub.transform; },
				Comparator.less, 100.0),
			{ shadowGoal.markSuccess(); },
			true, 60_000_000L);
		addTrigger(shadowTrigger);

		// text hints
		m_syncState.mapElements.addElement("splithint",
			MapElement.text(MapText(
				vec2d(10, 20), 16), COLOR_HINT,
				"'two squares' button in top right corner splits the window"));
		m_syncState.mapElements.addElement("zoomhint",
			MapElement.text(MapText(
				vec2d(10, 0), 16), COLOR_HINT,
				"zoom out for more hints"));
		m_syncState.mapElements.addElement("activesonar",
			MapElement.text(MapText(
				vec2d(200, -200), 14), COLOR_HINT,
`Press F4 and click 'Ping' button in upper left corner. Create contact by
right-clicking a blip on sonar image and selecting 'new contact'.
Verify contact position on tactical map (F1).

Go back to sonar. You can zoom and pan sonar image, just like on a tactical map.
Wait for 20 seconds and ping again, then drag a contact's pictogram to
follow the blip. Repeat this process 4-5 times, then click on the contact's
yellow pictogram on a tactical map.

This is the TMA mode. Drag the edge of a yellow rhombus around using left mouse button.
Drag the edge of a big white circle to edit solution velocity. These manipulations
alter your assumptions about the target's current position and velocity.
Transparent moving shadow of a contact is a current position of the target as
predicted by your solution. Click on empty space to finalize the solution.

The solution is good if it conforms to sensor data. Enter TMA mode by clicking
on the contact icon again. Now drag it and change it's velocity in such a way that
the purple 'legs' that are tied to small red squares have minimal sweep.
Small red squares are the sonar data samples. You generate them by dragging
contact pictogram on the sonar screen after each new ping.
Velocity can be edited more precisely by dragging the yellow 'tail ray'
of the selected contact.
Try clicking with right mouse button on the red square and selecting 'pivot here'.
This will move solution to precisely match sonar data sample in space and time.

Tip: you do not need to wait until the image update reaches
the top of active sonar screen, pings can be made every 5 seconds.

Ping some more, check that new red squares are close to your solution.
When satisfied with precision, complete the mission's objective.`));
	}
}