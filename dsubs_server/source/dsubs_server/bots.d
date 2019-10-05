module dsubs_server.bots;

import std.algorithm;
import std.array: array;
import std.random;

import dsubs_common.event;
import dsubs_common.math;

import dsubs_server.common;
import dsubs_server.submarine: Submarine;
import dsubs_server.weaponry;
import dsubs_server.player;
import dsubs_server.ai.captain;


/// Simple bot captain that just swims to his destination.
final class BotCaptain: AICrewTemp
{
	override @property string name() const { return "BOT Captain"; }

	this()
	{
		m_destination = vec2d(0, 0);
	}

	private
	{
		vec2d m_destination;
		float m_chosenThrottle = 1.0f;
		bool m_reachedDest;
		enum float DEST_TOLERANCE = 200.0f;
	}

	@property void destination(vec2d rhs)
	{
		m_destination = rhs;
		m_reachedDest = false;
		m_chosenThrottle = uniform!("[]")(0.4f, 1.0f);
	}

	@property bool reachedDestination() const { return m_reachedDest; }

	override void afterSimulation()
	{
		if (m_submarine is null || m_submarine.dead)
			return;
		vec2d diff = m_destination - m_submarine.transform.wposition;
		m_reachedDest = DEST_TOLERANCE >= diff.length;
		if (m_reachedDest)
			m_submarine.targetThrottle = 0.0f;
		else
		{
			m_submarine.targetThrottle = m_chosenThrottle;
			m_submarine.targetCourse = courseAngle(diff);
		}
	}
}


final class BotCollection
{
	private
	{
		bool[AICrewTemp] m_bots;
	}

	@property auto captains() { return m_bots.byKey; }

	@property BotCaptain[] botCaptains() { return cast(BotCaptain[]) m_bots.byKey.array; }

	@property size_t count() const { return m_bots.length; }

	void clean()
	{
		m_bots.clear();
	}

	void registerEntity(AICrewTemp cpt)
	{
		m_bots[cpt] = true;
	}

	void onAfterSimulation()
	{
		// remove captains with dead submarines
		AICrewTemp[] cptToRemove = m_bots.byKey.filter!(cpt =>
			cpt.submarine && cpt.submarine.dead).array;
		foreach (AICrewTemp cpt; cptToRemove)
			m_bots.remove(cpt);
		// alive captains need an update
		foreach (AICrewTemp bcpt; Globals.taskPool.parallel(m_bots.keys, 1))
			bcpt.afterSimulation();
	}
}