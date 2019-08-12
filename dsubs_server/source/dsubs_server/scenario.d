module dsubs_server.scenario;

import std.random: uniform, uniform01;

import dsubs_common.math.angles: courseVector;
import dsubs_common.api.protocols.backend: SpawnReq;

import dsubs_server.common;
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
		m_currentCenter = vec2d(uniform(-float(DEFAULT_RADIUS), float(DEFAULT_RADIUS)));
		m_nextTransitionTime = Globals.sim.worldTime + STABLE_TIME;
	}

	override void onBeforeSimulation() {}

	override void onAfterSimulation() {}

	override void selectPlayerSpawnPosition(Player p, const SpawnReq req,
		out vec2d position, out double rotation)
	{
		float fromCenter = (0.5f + (uniform01 * 0.5f)) * m_currentRadius;
		float angularCoord = uniform(0.0f, 2 * PI);
		position = m_currentCenter + fromCenter * courseVector(angularCoord);
		rotation = uniform(0.0f, 2 * PI);
	}
}