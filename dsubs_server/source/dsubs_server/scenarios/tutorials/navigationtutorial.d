module dsubs_server.scenarios.tutorials.navigationtutorial;

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
`You'll need to complete a set of simple navigational excercises that develop propulsion and helm control.`;
		constants.allowedEntities = EntityDbShort(["Stork"], ["Seven-blade screw"]);
		return constants;
	}

	private
	{
		Transform2D[] m_waypointTransforms;
	}

	void setupWaypointGoal(size_t idx)
	{
		string wptNum = (idx + 1).to!string;
		SimpleGoal wptGoal = new SimpleGoal("approach WPT" ~ wptNum,
			"Get into 100m distance from the WPT" ~ wptNum ~ " waypoint. " ~
			"Use 'C' hotkey to focus course control.");
		addVisibleGoal(wptGoal);
		m_syncState.mapElements.addElement("wpt" ~ wptNum,
			MapElement.circle(MapCircle(
				m_waypointTransforms[idx].wposition, 100, 3), COLOR_WAYPOINT));
		m_syncState.mapElements.addElement("wptlbl" ~ wptNum,
			MapElement.text(MapText(
				m_waypointTransforms[idx].wposition, 16), COLOR_WAYPOINT,
				"WPT" ~ wptNum));
		usecs_t activationTime = 0;
		if (idx == m_waypointTransforms.length - 1)
		{
			activationTime = 30 * 1000_000;
			wptGoal.shortText = "stop in WPT" ~ wptNum;
			wptGoal.longText = wptGoal.longText ~
				" and stay in the circle for 30 seconds. " ~
				"To break/reverse, enter -100 to 'tgt throttle' field.";
		}
		ScenarioTrigger wptTrigger = new ScenarioTrigger(
			new DistanceCondition(
				{ return m_waypointTransforms[idx]; },
				{ return m_playerSub.transform; },
				Comparator.less, 100.0),
			{
				wptGoal.markSuccess();
				m_syncState.mapElements.removeElement("wpt" ~ wptNum);
				m_syncState.mapElements.removeElement("wptlbl" ~ wptNum);
				if (idx < m_waypointTransforms.length - 1)
					setupWaypointGoal(idx + 1);
			}, true, activationTime);
		addTrigger(wptTrigger);
	}

	this(Simulator sim)
	{
		super(sim, ChatMessage(longUnixTime(), ChatMessageType.scenarioNotice,
			"Welcome to navigation tutorial"));
		m_victoryLongReport =
		`Maneuvering on the theatre will now be an easy task for you.`;
		m_waypointTransforms ~= new Transform2D(vec2d(0.0, 500.0));
		m_waypointTransforms ~= new Transform2D(vec2d(550.0, 750.0));
		m_waypointTransforms ~= new Transform2D(vec2d(450.0, 0.0));

		setupWaypointGoal(0);

		Goal speedGoal = new SimpleGoal("build up speed of 8m/s",
			"Using throttle control in the bottom of the screen (T hotkey), enter " ~
			"a number from 70 to 100 to speed up to 8 m/s.");
		addVisibleGoal(speedGoal);
		ScenarioTrigger speedTrigger = new ScenarioTrigger(
			new SpeedCondition({ return m_playerSub; },
				Comparator.greaterOrEqual, 8.0),
			{ speedGoal.markSuccess(); });
		addTrigger(speedTrigger);

		// text hints
		m_syncState.mapElements.addElement("zoomhint",
			MapElement.text(MapText(
				vec2d(-20, 0), 16), COLOR_HINT,
				"mouse wheel to zoom"));
		m_syncState.mapElements.addElement("panhint",
			MapElement.text(MapText(
				vec2d(-400, 300), 16), COLOR_HINT,
				"hold right mouse button to pan"));
		m_syncState.mapElements.addElement("coursehint",
			MapElement.text(MapText(
				vec2d(400, 600), 16), COLOR_HINT,
				"right mouse button -> set course towards"));
	}
}