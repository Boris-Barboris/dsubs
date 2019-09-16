module dsubs_server.scenario;

import std.algorithm: min, max;
import std.random: uniform, uniform01;
import std.datetime.systime;

import dsubs_common.math.angles;
import dsubs_common.api.protocols.backend;
import dsubs_common.api.entities;

import dsubs_server.common;
import dsubs_server.vessel;
import dsubs_server.weaponry;
import dsubs_server.submarine: Submarine;
import dsubs_server.connections.playercon: PlayerConnection;
import dsubs_server.player: Player;
import dsubs_server.bots;


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


int intUnixTime()
{
	return Clock.currTime.toUnixTime.to!int;
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

		struct ReloadCircle
		{
			vec2d center;
		}
		ReloadCircle[Player] m_playerReloadCircles;

		enum float DEFAULT_RADIUS = 5000.0f;
		enum float ESTIMATE_SPD = 13.5f;
		enum float PER_PLAYER_EXPANSION = 500.0f;
		enum float RELOAD_CIRCLE_RADIUS = 120.0f;
		enum int TORPS_TO_RELOAD = 3;
		enum int DECOYS_TO_RELOAD = 6;
		enum usecs_t STABLE_TIME = 40 * 60 * 1000_000;
		enum int ACTIVE_BOTS = 3;
	}

	this()
	{
		m_currentRadius = DEFAULT_RADIUS;
		m_currentCenter = vec2d(
			uniform(-float(DEFAULT_RADIUS), float(DEFAULT_RADIUS)),
			uniform(-float(DEFAULT_RADIUS), float(DEFAULT_RADIUS)));
		m_nextCenter = m_currentCenter;
		m_nextRadius = m_currentRadius;
		//m_nextTransitionTime = Globals.sim.worldTime + 120_000_000;
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
				if (!sub.dead && sub.player)
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
		// spawn bots if necessary
		int botsToSpawn = ACTIVE_BOTS - Globals.bots.count.to!int;
		while (botsToSpawn-- > 0)
		{
			info("Spawning new bot");
			BotCaptain cpt = new BotCaptain();
			SpawnReq req = SpawnReq("Bot trader", "Civilian three-blade screw");
			Submarine botSub = Globals.entityDb.buildSubFromLoadout(req, cpt);
			vec2d spawnPos;
			double spawnRot;
			getRandomSpawn(spawnPos, spawnRot);
			botSub.transform.position = spawnPos;
			botSub.transform.rotation = spawnRot;
			foreach (h; botSub.hydrophones)
				h.active = false;
			Globals.bots.registerEntity(cpt);
			cpt.destination = getDistantPos(spawnPos);
			botSub.register();
		}
		// give new destinations to bots that have arrived
		foreach (BotCaptain cpt; Globals.bots.captains)
		{
			if (cpt.reachedDestination)
				cpt.destination = getDistantPos(cpt.submarine.transform.wposition);
		}
	}

	/// make sure each alive player submarine has a reload circle
	private void synchronizeReloadCircles()
	{
		auto allPlayers = Globals.players.players.values;
		foreach (Player p; allPlayers)
		{
			if (p.hasAliveSub)
				ensureReloadCircleForPlayer(p);
			else
				m_playerReloadCircles.remove(p);
		}
	}

	private ReloadCircle generateReloadCirclePos(Submarine sub)
	{
		return ReloadCircle(getDistantPos(sub.transform.wposition));
	}

	private vec2d getDistantPos(vec2d pos)
	{
		double dist = 0.0;
		vec2d res;
		while (dist <= 0.8 * m_nextRadius)
		{
			res = m_nextCenter + rotateVector(
				vec2d(0, m_nextRadius * (0.65 + 0.3 * uniform01)),
				uniform(0, 2 * PI));
			dist = (pos - res).length;
		}
		return res;
	}

	private void ensureReloadCircleForPlayer(Player p)
	{
		Submarine s = p.submarine;
		assert(s !is null);
		ReloadCircle* rc = p in m_playerReloadCircles;
		if (rc is null)
			m_playerReloadCircles[p] = generateReloadCirclePos(s);
	}

	// check submarine positions and add random ammo if needed.
	private void triggerReloadCircles()
	{
		Player[] triggeredPlayers;
		int unixTime = intUnixTime();
		foreach (playerRcPair; m_playerReloadCircles.byKeyValue)
		{
			Player p = playerRcPair.key;
			ReloadCircle rc = playerRcPair.value;
			Submarine s = p.submarine;
			if (RELOAD_CIRCLE_RADIUS >= (s.transform.wposition - rc.center).length)
			{
				reloadSubmarine(p, s);
				triggeredPlayers ~= p;
			}
		}
		foreach (Player p; triggeredPlayers)
		{
			m_playerReloadCircles.remove(p);
			ensureReloadCircleForPlayer(p);
			PlayerConnection pcon = p.connection;
			if (pcon)
			{
				MapOverlayUpdateRes mapBcst;
				ChatMessageRes textBcst;
				generateBriefing(p, mapBcst.mapElements, textBcst.message);
				textBcst.message = ChatMessage(unixTime,
					"Weapon racks reloaded. New reload point allocated.");
				pcon.sendMessage(cast(immutable) mapBcst);
				pcon.sendMessage(cast(immutable) textBcst);
			}
		}
	}

	private void reloadSubmarine(Player p, Submarine s)
	{
		PlayerConnection pcon = p.connection;
		foreach (AmmoRoom room; s.ammoRoomRange)
		{
			int maxWeaponsToLoad =
				room.prototype.roomType == TubeType.standard ?
				TORPS_TO_RELOAD : DECOYS_TO_RELOAD;
			int weaponsToLoad = min(maxWeaponsToLoad, room.capacity - room.weaponCount);
			if (weaponsToLoad > 0)
			{
				string[] allowedWeapons = room.prototype.allowedWeaponSet.keys;
				while (weaponsToLoad-- > 0)
				{
					string weaponName = allowedWeapons[
						uniform(0, allowedWeapons.length)];
					room.putWeapon(weaponName);
				}
				// send room update if possible
				if (pcon)
				{
					pcon.sendMessage(cast(immutable)
						AmmoRoomStateUpdateRes(room.fullState));
				}
			}
		}
	}

	override void onAfterSimulation()
	{
		synchronizeReloadCircles();
		triggerReloadCircles();
		// check if it's time for transition
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
				m_nextRadius = DEFAULT_RADIUS + PER_PLAYER_EXPANSION *
					max(0, Player.getPlayersOnline() - 1);
				m_nextCenter = m_currentCenter + rotateVector(
					vec2d(0, m_currentRadius + m_nextRadius),
					uniform(0, 2 * PI));
				usecs_t transitionTime = cast(usecs_t)
					((m_currentRadius + m_nextRadius) / ESTIMATE_SPD) * 1000_000;
				m_nextTransitionTime = Globals.sim.worldTime + transitionTime;
				info("Scenario arena transition has started");
				// regenerate reload circles
				m_playerReloadCircles.clear();
				synchronizeReloadCircles();
			}
			m_inTransition = !m_inTransition;
			// send message(s) to active players
			Globals.players.forEachAliveConnectedPlayer(
				(Player p, Submarine sub, PlayerConnection pcon)
				{
					MapOverlayUpdateRes mapBcst;
					ChatMessageRes textBcst;
					generateBriefing(p, mapBcst.mapElements, textBcst.message);
					pcon.sendMessage(cast(immutable) textBcst);
					pcon.sendMessage(cast(immutable) mapBcst);
				});
			// give new destinations to bots
			foreach (BotCaptain cpt; Globals.bots.captains)
			{
				cpt.destination = getDistantPos(cpt.submarine.transform.wposition);
			}
		}
	}

	override void generateBriefing(Player player,
		out MapElement[] mapOverlayEls, out ChatMessage briefing)
	{
		int unixTime = intUnixTime();
		// circle for next/active arena
		MapElementUnion arenaCircleUnion;
		arenaCircleUnion.circle = MapCircle(
			player.posToClientSpace(m_nextCenter), m_nextRadius, 4.0f);
		mapOverlayEls ~= MapElement(
			MapElementType.circle,
			arenaCircleUnion,
			"arena",
			RgbaColor(3, 0, 204, 150));
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
		// circle for reloading area
		ensureReloadCircleForPlayer(player);
		MapElementUnion reloadCircleUnion;
		reloadCircleUnion.circle = MapCircle(
			player.posToClientSpace(m_playerReloadCircles[player].center),
			RELOAD_CIRCLE_RADIUS, 2.0f);
		mapOverlayEls ~= MapElement(
			MapElementType.circle,
			reloadCircleUnion,
			"reload here",
			RgbaColor(187, 212, 0, 150));
	}

	private void getRandomSpawn(out vec2d position, out double rotation)
	{
		float fromCenter = (0.6f + (uniform01 * 0.35f)) * m_nextRadius;
		float angularCoord = uniform(0.0f, 2 * PI);
		position = m_nextCenter + fromCenter * courseVector(angularCoord);
		rotation = uniform(0.0f, 2 * PI);
	}

	override void selectPlayerSpawnPosition(Player p, const SpawnReq req,
		out vec2d position, out double rotation)
	{
		getRandomSpawn(position, rotation);
	}
}