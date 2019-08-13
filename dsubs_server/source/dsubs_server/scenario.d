module dsubs_server.scenario;

import std.random: uniform, uniform01;

import dsubs_common.math.angles;
import dsubs_common.api.protocols.backend: SpawnReq;

import dsubs_server.common;
import dsubs_server.vessel;
import dsubs_server.submarine: Submarine;
import dsubs_server.player: Player;


abstract class Scenario
{
	@property string name() const
	{
		return this.classinfo.name;
	}

	abstract void onBeforeSimulation();

	abstract void onAfterSimulation();

	abstract void selectPlayerSpawnPosition(Player player, const SpawnReq req,
		out vec2d position, out double rotation);
}


final class BattleRoyale: Scenario
{
	private
	{
		vec2d m_currentCenter;
		double m_currentRadius;
		vec2d m_nextCenter;
		double m_nextRadius;
		usecs_t m_nextTransitionTime;
		bool m_inTransition;

		enum FLOAT DEFAULT_RADIUS = 10000.0f;
		enum usecs_t STABLE_TIME = 25 * 60 * 1000_000;
		enum usecs_t TRANSITION_TIME = 5 * 60 * 1000_000;
	}

	this()
	{
		m_currentRadius = DEFAULT_RADIUS;
		m_currentCenter = vec2d(
			uniform(-float(DEFAULT_RADIUS), float(DEFAULT_RADIUS)),
			uniform(-float(DEFAULT_RADIUS), float(DEFAULT_RADIUS)));
		m_nextTransitionTime = Globals.sim.worldTime + STABLE_TIME;
	}

	override void onBeforeSimulation()
	{
		if (!m_inTransition)
		{
			// we need to force all played submarines to stay in circle
			foreach (Vessel v; Globals.vessels.entities)
			{
				Submarine sub = cast(Submarine) v;
				if (sub is null)
					continue;
				if (!sub.dead && sub.owner)
				{
					vec2d diffVec = m_currentCenter - sub.transform.wposition;
					if (diffVec.length > m_currentRadius)
					{
						// force throttle to flank and set course to center of
						// the circle.
						sub.targetThrottle = 1.0f;
						sub.targetCourse = courseAngle(diffVec);
					}
				}
			}
		}
	}

	override void onAfterSimulation()
	{
		if (Globals.sim.worldTime >= m_nextTransitionTime)
		{
			if (m_inTransition)
			{
				m_currentCenter = m_nextCenter;
				m_currentRadius = m_nextRadius;
				m_nextTransitionTime = Globals.sim.worldTime + STABLE_TIME;
			}
			else
			{
				// TODO: generate new nextCenter and nextRadius
				m_nextTransitionTime = Globals.sim.worldTime + TRANSITION_TIME;
			}
			m_inTransition = !m_inTransition;
			// TODO: send message
		}
	}

	override void selectPlayerSpawnPosition(Player p, const SpawnReq req,
		out vec2d position, out double rotation)
	{
		float fromCenter = (0.5f + (uniform01 * 0.5f)) * m_currentRadius;
		float angularCoord = uniform(0.0f, 2 * PI);
		position = m_currentCenter + fromCenter * courseVector(angularCoord);
		rotation = uniform(0.0f, 2 * PI);
	}
}