module dsubs_server.scenario;

import std.random: uniform, uniform01;
import std.datetime.systime;

import dsubs_common.math.angles;
import dsubs_common.api.protocols.backend: SpawnReq, MapOverlayUpdateRes, ChatMessageRes;
import dsubs_common.api.entities;

import dsubs_server.common;
import dsubs_server.vessel;
import dsubs_server.submarine: Submarine;
import dsubs_server.connections.playercon: PlayerConnection;
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

	/// scenario generates initial overlay state and briefing
	abstract void generateBriefing(Player player, out MapElement[] mapOverlayEls,
		out ChatMessage briefing);
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

		enum float DEFAULT_RADIUS = 5000.0f;
		enum float ESTIMATE_SPD = 13.5f;
		enum usecs_t STABLE_TIME = 15 * 60 * 1000_000;
		enum usecs_t TRANSITION_TIME = cast(usecs_t) (2 * DEFAULT_RADIUS / ESTIMATE_SPD) * 1000_000;
	}

	this()
	{
		m_currentRadius = DEFAULT_RADIUS;
		m_currentCenter = vec2d(
			uniform(-float(DEFAULT_RADIUS), float(DEFAULT_RADIUS)),
			uniform(-float(DEFAULT_RADIUS), float(DEFAULT_RADIUS)));
		m_nextCenter = m_currentCenter;
		m_nextRadius = m_currentRadius;
		m_nextTransitionTime = Globals.sim.worldTime + 120_000_000;
		// m_nextTransitionTime = Globals.sim.worldTime + STABLE_TIME;
	}

	override void onBeforeSimulation()
	{
		if (!m_inTransition)
		{
			// we need to force all played submarines to stay in circle.
			// we are doing it my making them go flank and setting rudder's
			// target course to the center of the circle.
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
				info("Scenario arena transition has finished");
			}
			else
			{
				// TODO: generate new nextCenter and nextRadius
				m_nextCenter = m_currentCenter + rotateVector(vec2d(0, m_currentRadius * 2), uniform(0, 2 * PI));
				m_nextRadius = m_currentRadius;
				m_nextTransitionTime = Globals.sim.worldTime + TRANSITION_TIME;
				info("Scenario arena transition has started");
			}
			m_inTransition = !m_inTransition;
			// send message(s) to active players
			Globals.players.forEachAlivePlayer(
				(Player p, Submarine sub, PlayerConnection pcon)
				{
					MapOverlayUpdateRes mapBcst;
					ChatMessageRes textBcst;
					generateBriefing(p, mapBcst.mapElements, textBcst.message);
					pcon.sendMessage(cast(immutable) textBcst);
					pcon.sendMessage(cast(immutable) mapBcst);
				});
		}
	}

	override void generateBriefing(Player player,
		out MapElement[] mapOverlayEls, out ChatMessage briefing)
	{
		int unixTime = Clock.currTime.toUnixTime.to!int;
		// circle for next/active arena
		MapElementUnion arenaCircleUnion;
		arenaCircleUnion.circle = MapCircle(
			player.posToClientSpace(m_nextCenter), m_nextRadius, 5.0f);
		mapOverlayEls ~= MapElement(
			MapElementType.circle,
			arenaCircleUnion,
			"arena",
			RgbaColor(3, 0, 204, 200));
		if (m_inTransition)
		{
			briefing = ChatMessage(
				unixTime,
				"New arena position, hurry to the blue circle! " ~
				"Time until forced navigation: " ~
				((m_nextTransitionTime - Globals.sim.worldTime) / 1000_000).
					to!string ~ " seconds.");
		}
		else
		{
			briefing = ChatMessage(
				unixTime,
				"Navigation limited to blue circle!");
		}
	}

	override void selectPlayerSpawnPosition(Player p, const SpawnReq req,
		out vec2d position, out double rotation)
	{
		float fromCenter = (0.6f + (uniform01 * 0.35f)) * m_currentRadius;
		float angularCoord = uniform(0.0f, 2 * PI);
		position = m_currentCenter + fromCenter * courseVector(angularCoord);
		rotation = uniform(0.0f, 2 * PI);
	}
}