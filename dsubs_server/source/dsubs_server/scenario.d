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
	abstract void generateBriefing(Player player, Submarine sub,
		out MapElement[] mapOverlay, pit ChatMessage briefing);
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

		enum float DEFAULT_RADIUS = 7000.0f;
		enum float ESTIMATE_SPD = 13.5f;
		enum usecs_t STABLE_TIME = 20 * 60 * 1000_000;
		enum usecs_t TRANSITION_TIME = cast(usecs_t) (2 * DEFAULT_RADIUS / ESTIMATE_SPD) * 1000_000;
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
				log.info("Scenario arena transition has finished");
			}
			else
			{
				// TODO: generate new nextCenter and nextRadius
				m_nextCenter = m_currentCenter + rotateVector(vec2d(0, m_currentRadius * 2), uniform(0, 2 * PI));
				m_nextRadius = m_currentRadius;
				m_nextTransitionTime = Globals.sim.worldTime + TRANSITION_TIME;
				log.info("Scenario arena transition has started");
			}
			// send message(s) to active players
			MapOverlayUpdateRes mapBcst;
			ChatMessageRes textBcst;
			int unixTime = Clock.currTime.toUnixTime.to!int;
			// circle for next/active arena
			MapElementUnion arenaCircleUnion;
			arenaCircleUnion.circle = MapCircle(
				m_nextCenter, m_nextRadius, 5.0f);
			mapBcst.mapElements ~= MapElement(
				MapElementType.circle,
				arenaCircleUnion,
				"arena",
				RgbaColor(3, 0, 204, 200));
			if (!m_inTransition)
			{
				// the transition has started, we need to draw the old arena as well
				MapElementUnion oldArenaCircleUnion;
				oldArenaCircleUnion.circle = MapCircle(
					m_currentCenter, m_currentRadius, 5.0f);
				mapBcst.mapElements ~= MapElement(
					MapElementType.circle,
					arenaCircleUnion,
					"old arena",
					RgbaColor(110, 110, 110, 200));
				textBcst.message = ChatMessage(
					unixTime,
					"New arena position, hurry to the blue circle! " ~
					"Time until forced navigation: " ~
					(TRANSITION_TIME / 1000_000).to!string ~ " seconds."
				);
			}
			else
			{
				textBcst.message = ChatMessage(
					unixTime,
					"New arena is enforced now!");
			}
			Globals.players.forEachAlivePlayer(
				(Player p, Submarine sub, PlayerConnection pcon)
				{
					pcon.sendMessage(cast(immutable) textBcst);
					pcon.sendMessage(cast(immutable) mapBcst);
				});
			m_inTransition = !m_inTransition;
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