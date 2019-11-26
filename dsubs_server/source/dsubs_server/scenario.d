module dsubs_server.scenario;

import std.algorithm;
import std.array: array;
import std.random: uniform, uniform01;
import std.container.rbtree;
import std.datetime.systime;

import dsubs_common.math.angles;
import dsubs_common.api.protocols.backend;
import dsubs_common.api.entities;

import dsubs_server.common;
import dsubs_server.vessel;
import dsubs_server.animal;
import dsubs_server.weaponry;
import dsubs_server.submarine: Submarine;
import dsubs_server.connections.playercon: PlayerConnection;
import dsubs_server.player;
import dsubs_server.bots;
import dsubs_server.ai.captain;
import dsubs_server.ai.common;


struct DelayedEvent
{
	usecs_t when;
	void delegate() operation;
}

alias DelayedEventCollection = RedBlackTree!(DelayedEvent, "a.when < b.when", true);

struct CallbackDelayer
{
	private DelayedEventCollection m_events;

	void initialize()
	{
		m_events = new DelayedEventCollection();
	}

	void put(DelayedEvent event)
	{
		m_events.insert(event);
	}

	void runCallbacks()
	{
		auto toRun = m_events.lowerBound(DelayedEvent(Globals.sim.worldTime));
		foreach (DelayedEvent evt; toRun)
			evt.operation();
		m_events.remove(toRun);
	}
}


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
		CallbackDelayer m_delayer;
		int m_civBotSpawnRequests;
		SideOfConflict m_botSide;

		struct ReloadCircle
		{
			vec2d center;
		}
		ReloadCircle[Player] m_playerReloadCircles;

		enum float DEFAULT_RADIUS = 5000.0f;
		enum float ESTIMATE_SPD = 12.0f;
		enum float PER_PLAYER_EXPANSION = 500.0f;
		enum float RELOAD_CIRCLE_RADIUS = 120.0f;
		enum int TORPS_TO_RELOAD = 3;
		enum int DECOYS_TO_RELOAD = 6;
		enum usecs_t SPAWN_DELAY_BASE = cast(usecs_t) 1 * 60 * 1000_000;
		enum usecs_t STABLE_TIME = cast(usecs_t) 60 * 60 * 1000_000;
		enum int ACTIVE_CIVILIAN_BOTS = 3;
		enum int MAX_ACTIVE_EASY_BOTS = 3;
		enum int MAX_ACTIVE_MEDIUM_BOTS = 4;

		/// we despawn combat bots after this time of zero active
		/// players.
		enum usecs_t DESPAWN_COMBAT_BOTS = cast(usecs_t) 60 * 60 * 1000_000;
		usecs_t m_lastSeenPlayer;

		bool[Submarine] m_civilianBots;
		bool[Submarine] m_easyBots;
		bool[Submarine] m_mediumBots;
	}

	this()
	{
		m_delayer.initialize();
		m_currentRadius = DEFAULT_RADIUS;
		m_currentCenter = vec2d(
			uniform(-float(DEFAULT_RADIUS), float(DEFAULT_RADIUS)),
			uniform(-float(DEFAULT_RADIUS), float(DEFAULT_RADIUS)));
		m_nextCenter = m_currentCenter;
		m_nextRadius = m_currentRadius;
		//m_nextTransitionTime = Globals.sim.worldTime + 120_000_000;
		m_nextTransitionTime = Globals.sim.worldTime + STABLE_TIME;
		m_botSide = new SideOfConflict("bots");
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
		m_delayer.runCallbacks();
		// trader bots
		int botsToSpawn = ACTIVE_CIVILIAN_BOTS - m_civBotSpawnRequests -
			Globals.bots.captains.filter!(b => b.submarine.prototypeName == "Bot trader").
			count.to!int;

		void delayCivilianBotSpawn(usecs_t delay)
		{
			m_delayer.put(DelayedEvent(Globals.sim.worldTime + delay,
				{
					info("Spawning new trader bot");
					m_civBotSpawnRequests--;
					AICrew crew = new AICrew(BOT_DIFFICULTY.easy);
					crew.side = m_botSide;
					SpawnReq req = SpawnReq("Bot trader", "Civilian three-blade screw");
					Submarine botSub = Globals.entityDb.buildSubFromLoadout(req, crew);
					vec2d spawnPos;
					double spawnRot;
					getRandomSpawn(spawnPos, spawnRot);
					botSub.transform.position = spawnPos;
					botSub.transform.rotation = spawnRot;
					m_civilianBots[botSub] = true;
					foreach (h; botSub.hydrophones)
						h.active = false;
					Globals.bots.registerEntity(crew);
					crew.goal = new SwimToDestinationGoal(crew, getDistantPos(spawnPos));
					botSub.register();
				}));
		}

		while (botsToSpawn-- > 0)
		{
			info("Scheduling new civilian bot spawn");
			usecs_t delay = uniform!("(]", usecs_t, usecs_t)(0, SPAWN_DELAY_BASE);
			m_civBotSpawnRequests++;
			delayCivilianBotSpawn(delay);
		}

		// for each dead civilian bot spawn easy bot
		void delayEasyBotSpawn(usecs_t delay)
		{
			m_delayer.put(DelayedEvent(Globals.sim.worldTime + delay,
				{
					info("Spawning new easy combat bot");
					AICrew crew = new AICrew(BOT_DIFFICULTY.easy);
					crew.side = m_botSide;
					SpawnReq req = SpawnReq("Stork", "Seven-blade screw",
						[AmmoRoomFullState(0, [WeaponCount("Minoga", 15)])]);
					Submarine botSub = Globals.entityDb.buildSubFromLoadout(req, crew);
					vec2d spawnPos;
					double spawnRot;
					getRandomSpawn(spawnPos, spawnRot);
					botSub.transform.position = spawnPos;
					botSub.transform.rotation = spawnRot;
					Globals.bots.registerEntity(crew);
					m_easyBots[botSub] = true;
					crew.goal = new SwimToDestinationGoal(crew, getDistantPos(spawnPos));
					botSub.register();
				}));
		}

		// easy combat bots
		int deadBotTraders = m_civilianBots.byKey.filter!(s => s.dead &&
			s.prototypeName == "Bot trader").count.to!int;
		int aliveEasyBots = m_easyBots.byKey.filter!(s => !s.dead).count.to!int;
		int easyBotsToSpawn = min(deadBotTraders, MAX_ACTIVE_EASY_BOTS - aliveEasyBots);
		while (easyBotsToSpawn-- > 0)
		{
			info("Scheduling new easy combat bot spawn");
			usecs_t delay = uniform!("(]", usecs_t, usecs_t)(0, SPAWN_DELAY_BASE);
			delayEasyBotSpawn(delay);
		}

		// for each dead easy bot spawn medium bot
		void delayMediumBotSpawn(usecs_t delay)
		{
			m_delayer.put(DelayedEvent(Globals.sim.worldTime + delay,
				{
					info("Spawning new medium combat bot");
					AICrew crew = new AICrew(BOT_DIFFICULTY.medium);
					crew.side = m_botSide;
					SpawnReq req = SpawnReq("Stork", "Seven-blade screw",
						[AmmoRoomFullState(0, [WeaponCount("Minoga", 8)]),
						AmmoRoomFullState(1, [WeaponCount("Decoy(active)", 15)])],
						[TubeSpawnState(2, "Decoy(active)"),
						TubeSpawnState(3, "Decoy(active)")]);
					Submarine botSub = Globals.entityDb.buildSubFromLoadout(req, crew);
					vec2d spawnPos;
					double spawnRot;
					getRandomSpawn(spawnPos, spawnRot);
					botSub.transform.position = spawnPos;
					botSub.transform.rotation = spawnRot;
					Globals.bots.registerEntity(crew);
					m_mediumBots[botSub] = true;
					crew.goal = new SwimToDestinationGoal(crew, getDistantPos(spawnPos));
					botSub.register();
				}));
		}

		// medium combat bots
		int deadEasyBots = m_easyBots.byKey.filter!(s => s.dead).count.to!int;
		int aliveMediumBots = m_mediumBots.byKey.filter!(s => !s.dead).count.to!int;
		int mediumBotsToSpawn = min(deadEasyBots, MAX_ACTIVE_MEDIUM_BOTS - aliveMediumBots);
		while (mediumBotsToSpawn-- > 0)
		{
			info("Scheduling new medium combat bot spawn");
			usecs_t delay = uniform!("(]", usecs_t, usecs_t)(0, SPAWN_DELAY_BASE);
			delayMediumBotSpawn(delay);
		}

		// remove dead submarines from collections
		void clearDeadSubs(ref bool[Submarine] collection)
		{
			Submarine[] deadSubs = collection.byKey.filter!(s => s.dead).array;
			foreach (Submarine sub; deadSubs)
				collection.remove(sub);
		}

		clearDeadSubs(m_civilianBots);
		clearDeadSubs(m_easyBots);
		clearDeadSubs(m_mediumBots);

		// Despawn bots when players are long gone. Saves electricity and resets
		// difficulty.
		if (Player.getPlayersOnline)
			m_lastSeenPlayer = Globals.sim.worldTime;
		else if (Globals.sim.worldTime - m_lastSeenPlayer > DESPAWN_COMBAT_BOTS)
		{
			// we don't run this code every frame, so we update m_lastSeenPlayer
			m_lastSeenPlayer = Globals.sim.worldTime;
			Submarine[] subsToKill;
			foreach (Submarine sub; m_easyBots.byKey)
				subsToKill ~= sub;
			foreach (Submarine sub; m_mediumBots.byKey)
				subsToKill ~= sub;
			foreach (Submarine sub; subsToKill)
			{
				trace("Killing bot because of player inactivily: ", sub);
				sub.kill("No players");
			}
			m_easyBots.clear();
			m_mediumBots.clear();
		}

		// give new destinations to bots that have arrived
		foreach (AICrewTemp crewTemp; Globals.bots.captains)
		{
			AICrew crew = cast(AICrew) crewTemp;
			assert(crew);
			if (crew.goal is null || crew.goal.status == GoalStatus.succeeded)
			{
				crew.goal = new SwimToDestinationGoal(crew,
					getDistantPos(getDistantPos(crew.submarine.transform.wposition)));
			}
		}
		// spawn animals if necessary
		int whalesToSpawn = 1 - Globals.animals.entities.length.to!int;
		while (whalesToSpawn-- > 0)
		{
			info("Spawning whale");
			Animal animal = Globals.entityDb.getAnimalFactory("humpback").build();
			vec2d spawnPos;
			double spawnRot;
			getRandomSpawn(spawnPos, spawnRot);
			animal.transform.position = spawnPos;
			animal.transform.rotation = spawnRot;
			animal.destination = getDistantPos(spawnPos);
			animal.register();
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
		int attempts = 32;
		while (dist <= 0.8 * m_nextRadius && attempts-- > 0)
		{
			res = m_nextCenter + rotateVector(
				vec2d(0, m_nextRadius * (0.65 + 0.3 * uniform01)),
				uniform(0, 2 * PI));
			dist = (pos - res).length;
		}
		if (attempts <= 0)
			warning("getDistantPos got into infinite loop");
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
				info("Scenario arena transition has finished: ", Globals.sim.worldTime);
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
				info("Scenario arena transition has started: ", Globals.sim.worldTime);
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
			foreach (AICrewTemp crwTemp; Globals.bots.captains)
			{
				AICrew crew = cast(AICrew) crwTemp;
				assert(crew);
				crew.goal = new SwimToDestinationGoal(crew,
					getDistantPos(getDistantPos(crew.submarine.transform.wposition)));
			}
			foreach (Animal an; Globals.animals.entities)
				an.destination = getDistantPos(an.transform.wposition);
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
			RgbaColor(11, 2, 87, 150));
		if (m_inTransition)
		{
			briefing = ChatMessage(
				unixTime,
				"New arena position, hurry to the dark-blue circle! " ~
				"Time until forced navigation: " ~
				((m_nextTransitionTime - Globals.sim.worldTime) / 1000_000).
					to!string ~ " seconds.");
		}
		else
		{
			briefing = ChatMessage(
				unixTime,
				"Navigation limited to dark-blue circle!");
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
			RgbaColor(212, 201, 0, 150));
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