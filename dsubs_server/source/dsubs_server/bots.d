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
import dsubs_server.ai.aicaptain;
import dsubs_server.observable;


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

	override void updateObservableCache()
	{
		super.updateObservableCache();
		m_observableCache.stateUpdateJson["name"] = this.name;
		m_observableCache.stateUpdateJson["destination"] = this.m_destination.to!string;
		m_observableCache.stateUpdateJson["chosenThrottle"] = this.m_chosenThrottle;
		m_observableCache.stateUpdateJson["reachedDest"] = this.m_reachedDest;
	}
}


final class BotCollection: IObservableCollection
{
	private
	{
		bool[AICrewTemp] m_entities;
	}

	@property auto captains() { return m_entities.byKey; }

	@property size_t count() const { return m_entities.length; }

	void clean()
	{
		m_entities.clear();
	}

	void registerEntity(AICrewTemp cpt)
	{
		m_entities[cpt] = true;
	}

	void onAfterSimulation()
	{
		// remove captains with dead submarines
		AICrewTemp[] cptToRemove = m_entities.byKey.filter!(cpt =>
			cpt.submarine && cpt.submarine.dead).array;
		foreach (AICrewTemp cpt; cptToRemove)
			m_entities.remove(cpt);
		// alive captains need an update
		foreach (AICrewTemp bcpt; Globals.taskPool.parallel(m_entities.byKey, 1))
			bcpt.afterSimulation();
	}

	mixin ObservableCollectionCommonMethods!(captains);
}