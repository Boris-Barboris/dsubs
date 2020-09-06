module dsubs_server.scenarios.tutorials.navigation;

import std.algorithm;

import dsubs_common.api.messages;
import dsubs_common.api.entities;

import dsubs_server.common;
import dsubs_server.vessel;
import dsubs_server.scenario;
import dsubs_server.simulator;


final class NavigationTutorial: SinglePlayerScenario
{
	static AvailableScenarioConstants getConstants()
	{
		AvailableScenarioConstants constants;
		constants.name = "Navigation";
		constants.shortDescription = "Learn the basics of seamanship.";
		constants.fullDescription =
`You'll need to complete a set of simple navigational excercises for propulsion and helm control.`;
		constants.allowedEntities = EntityDbShort(["Stork"], ["Seven-blade screw"]);
		return constants;
	}

	private
	{
		Transform2D[] m_waypointTransforms;
		Goal m_speedGoal, m_wpt1Goal, m_wpt2Goal, m_wpt3Goal;
	}

	this(Simulator sim)
	{
		super(sim, ChatMessage(longUnixTime(), ChatMessageType.scenarioNotice,
			"Welcome to navigation tutorial"));
		m_victoryLongReport =
		`Maneuvering on the theatre will now be an easy task for you.`;
		m_waypointTransforms ~= new Transform2D(vec2d(0.0, 1500.0));
		m_waypointTransforms ~= new Transform2D(vec2d(1500.0, 1500.0));
		m_waypointTransforms ~= new Transform2D(vec2d(1000.0, -500.0));

		m_wpt1Goal = new SimpleGoal("approach waypoint",
			"Get into 100m distance from the waypoint 1");
		addVisibleGoal(m_wpt1Goal);
		ScenarioTrigger wpt1Trigger = new ScenarioTrigger(
			new DistanceCondition(
				{ return m_waypointTransforms[0]; },
				{ return m_playerSub.transform; },
				Comparator.less, 200.0),
			{ m_wpt1Goal.markSuccess(); });
		addTrigger(wpt1Trigger);

		m_speedGoal = new SimpleGoal("build up speed of 8m/s",
			"Using throttle control in the bottom of the screen, enter " ~
			"a number from 70 to 100 to speed up to 8 m/s");
		addVisibleGoal(m_speedGoal);
		ScenarioTrigger speedTrigger = new ScenarioTrigger(
			new SpeedCondition({ return m_playerSub; },
				Comparator.greaterOrEqual, 8.0),
			{ m_speedGoal.markSuccess(); });
		addTrigger(speedTrigger);
	}
}