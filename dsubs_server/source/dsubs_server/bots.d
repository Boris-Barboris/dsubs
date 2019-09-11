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


/// Simple bot captain that just swims to his destination.
final class BotCaptain: Captain
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
		m_chosenThrottle = uniform!("[]")(0.35f, 1.0f);
	}

	@property bool reachedDestination() const { return m_reachedDest; }

	void afterSimulation()
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
		bool[BotCaptain] m_captains;
	}

	@property auto captains() { return m_captains.byKey; }

	@property size_t count() const { return m_captains.length; }

	void clean()
	{
		m_captains.clear();
	}

	void registerEntity(BotCaptain cpt)
	{
		m_captains[cpt] = true;
	}

	void onAfterSimulation()
	{
		// remove captains with dead submarines
		BotCaptain[] cptToRemove = m_captains.byKey.filter!(cpt =>
			cpt.submarine && cpt.submarine.dead).array;
		foreach (BotCaptain cpt; cptToRemove)
			m_captains.remove(cpt);
		// alive captains need an update
		foreach (BotCaptain bcpt; Globals.taskPool.parallel(m_captains.keys, 1))
			bcpt.afterSimulation();
	}
}