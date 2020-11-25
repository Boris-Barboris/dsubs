module dsubs_server.scenarios.battleroyale;

import std.algorithm;
import std.array: array;
import std.random: uniform, uniform01;
import std.range: walkLength;
import std.container.rbtree;
import std.datetime.systime;

import dsubs_common.math.angles;
import dsubs_common.api.messages;
import dsubs_common.api.entities;

import dsubs_server.common;
import dsubs_server.vessel;
import dsubs_server.animal;
import dsubs_server.weaponry;
import dsubs_server.submarine: Submarine;
import dsubs_server.connections.playercon: PlayerConnection;
import dsubs_server.player;
import dsubs_server.bots;
import dsubs_server.scenario;
import dsubs_server.simulator;
import dsubs_server.ai.captain;
import dsubs_server.ai.common;




SpawnReq randomCombatSub()
{
	__gshared SpawnReq[] variations;
	if (variations is null)
	{
		variations = [
			SpawnReq("Stork", "Seven-blade screw",
						[AmmoRoomFullState(0, [WeaponCount("Minoga", 16)]),
						AmmoRoomFullState(1, [
							WeaponCount("Decoy(active)", 14),
							WeaponCount("Decoy(passive)", 14)])],
						[TubeSpawnState(2, "Decoy(active)"),
						TubeSpawnState(3, "Decoy(passive)")]),
			SpawnReq("Lima", "Five-blade Lima screw",
						[AmmoRoomFullState(0, [WeaponCount("Minoga", 14)]),
						AmmoRoomFullState(1, [
							WeaponCount("Decoy(active)", 11),
							WeaponCount("Decoy(passive)", 11)])],
						[TubeSpawnState(2, "Decoy(active)"),
						TubeSpawnState(3, "Decoy(passive)")]),
			SpawnReq("November", "Five-blade November screw",
						[AmmoRoomFullState(0, [WeaponCount("Minoga", 22)]),
						AmmoRoomFullState(1, [
							WeaponCount("Decoy(active)", 15),
							WeaponCount("Decoy(passive)", 15)])],
						[TubeSpawnState(3, "Decoy(active)"),
						TubeSpawnState(4, "Decoy(passive)")])
		];
	}
	return variations[uniform(0, variations.length)];
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
		AlarmCollection m_delayer;
		int m_civBotSpawnRequests;
		SideOfConflict m_botSide;
		bool m_singlePlayer;
		Submarine m_playerSub;

		Player[] m_newPlayers;

		struct ReloadCircle
		{
			vec2d center;
		}
		ReloadCircle[Player] m_playerReloadCircles;

		enum float DEFAULT_RADIUS = 7000.0f;
		enum float ESTIMATE_SPD = 12.0f;
		enum float PER_PLAYER_EXPANSION = 500.0f;
		enum float RELOAD_CIRCLE_RADIUS = 120.0f;
		enum int TORPS_TO_RELOAD = 3;
		enum int DECOYS_TO_RELOAD = 6;
		enum usecs_t SPAWN_DELAY_BASE = cast(usecs_t) 1 * 60 * 1000_000;
		enum usecs_t STABLE_TIME = cast(usecs_t) 60 * 60 * 1000_000;
		enum int ACTIVE_CIVILIAN_BOTS = 3;
		enum int MAX_ACTIVE_EASY_BOTS = 2;
		enum int MAX_ACTIVE_MEDIUM_BOTS = 2;

		/// we despawn combat bots after this time of zero active
		/// players.
		enum usecs_t DESPAWN_IDLE_INTERVAL = cast(usecs_t) 45 * 60 * 1000_000;
		usecs_t m_lastSeenPlayer;

		bool[Submarine] m_civilianBots;
		bool[Submarine] m_easyBots;
		bool[Submarine] m_mediumBots;
	}

	static AvailableScenarioConstants getConstants(bool singlePlayer)
	{
		AvailableScenarioConstants constants;
		constants.name = "Circle arena";
		if (singlePlayer)
			constants.name ~= " (SP)";
		constants.shortDescription = "Quick battle with infinite bots.";
		constants.fullDescription =
`Three civilian traders (propellers with 3 blades) are infinitely respawned for you to kill.
Each trader killed triggers an easy combat bot spawn.
Each easy combat bot killed spawns a medium combat bot.
Player movement is restricted by big blue circle, that sometimes moves.
You can rearm by swimming into the small yellow circle.

Pace your kills according to the amount of chaos you desire.
Good luck!`;
		if (!singlePlayer)
		{
			constants.fullDescription ~= "\n\n" ~
`You cannot abandon online games. The only way out is to torpedo yourself or disconnect for 30 minutes.`;
		}
		constants.allowedEntities = Globals.entityDb.getCompleteShortDb();
		return constants;
	}

	@property usecs_t lastSeenPlayer() const { return m_lastSeenPlayer; }

	static bool isHumanCaptain(Captain cpt)
	{
		return (cast(Player) cpt) !is null;
	}

	this(Simulator sim, bool singlePlayer = false)
	{
		super(sim);
		m_singlePlayer = singlePlayer;
		m_delayer.initialize();
		m_currentRadius = DEFAULT_RADIUS;
		m_currentCenter = vec2d(
			uniform(-float(DEFAULT_RADIUS), float(DEFAULT_RADIUS)),
			uniform(-float(DEFAULT_RADIUS), float(DEFAULT_RADIUS)));
		m_nextCenter = m_currentCenter;
		m_nextRadius = m_currentRadius;
		//m_nextTransitionTime = m_simulator.worldTime + 5_000_000;
		m_nextTransitionTime = m_simulator.worldTime + STABLE_TIME;
		m_botSide = new SideOfConflict("bots");
	}

	override void onBeforeSimulation()
	{
		if (!m_inTransition)
		{
			// we need to force all played submarines to stay in circle.
			// we are doing it my making them go flank and setting rudder's
			// target course to the center of the circle.
			foreach (Vessel v; m_simulator.vessels.entities)
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
		m_delayer.triggerAlarms(m_simulator.worldTime);
		// trader bots
		int botsToSpawn = ACTIVE_CIVILIAN_BOTS - m_civBotSpawnRequests -
			m_simulator.bots.captains.filter!(b => b.submarine.prototypeName == "Bot trader").
			count.to!int;

		void delayCivilianBotSpawn(usecs_t delay)
		{
			m_delayer.put(AlarmClockAction(m_simulator.worldTime + delay,
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
						h.shouldBeActive = false;
					m_simulator.bots.registerEntity(crew);
					crew.goal = new SwimToDestinationGoal(crew, getDistantPos(spawnPos));
					botSub.register(m_simulator);
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
			m_delayer.put(AlarmClockAction(m_simulator.worldTime + delay,
				{
					info("Spawning new easy combat bot");
					AICrew crew = new AICrew(BOT_DIFFICULTY.easy);
					crew.side = m_botSide;
					SpawnReq req = randomCombatSub();
					Submarine botSub = Globals.entityDb.buildSubFromLoadout(req, crew);
					vec2d spawnPos;
					double spawnRot;
					getRandomSpawn(spawnPos, spawnRot);
					botSub.transform.position = spawnPos;
					botSub.transform.rotation = spawnRot;
					m_simulator.bots.registerEntity(crew);
					m_easyBots[botSub] = true;
					crew.goal = new SwimToDestinationGoal(crew, getDistantPos(spawnPos));
					botSub.register(m_simulator);
				}));
		}

		// easy combat bots
		int deadBotTraders = m_civilianBots.byKey.filter!(s => s.dead &&
			s.prototypeName == "Bot trader" && isHumanCaptain(s.killer)).count.to!int;
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
			m_delayer.put(AlarmClockAction(m_simulator.worldTime + delay,
				{
					info("Spawning new medium combat bot");
					AICrew crew = new AICrew(BOT_DIFFICULTY.medium);
					crew.side = m_botSide;
					SpawnReq req = randomCombatSub();
					Submarine botSub = Globals.entityDb.buildSubFromLoadout(req, crew);
					vec2d spawnPos;
					double spawnRot;
					getRandomSpawn(spawnPos, spawnRot);
					botSub.transform.position = spawnPos;
					botSub.transform.rotation = spawnRot;
					m_simulator.bots.registerEntity(crew);
					m_mediumBots[botSub] = true;
					crew.goal = new SwimToDestinationGoal(crew, getDistantPos(spawnPos));
					botSub.register(m_simulator);
				}));
		}

		// medium combat bots
		int deadEasyBots = m_easyBots.byKey.filter!(s => s.dead &&
			isHumanCaptain(s.killer)).count.to!int;
		int aliveMediumBots = m_mediumBots.byKey.filter!(s => !s.dead).count.to!int;
		int mediumBotsToSpawn = min(deadEasyBots, MAX_ACTIVE_MEDIUM_BOTS - aliveMediumBots);
		while (mediumBotsToSpawn-- > 0)
		{
			info("Scheduling new medium combat bot spawn");
			usecs_t delay = uniform!("(]", usecs_t, usecs_t)(0, SPAWN_DELAY_BASE);
			delayMediumBotSpawn(delay);
		}

		// remove dead submarines from collections
		void clearDeadSubs(ref bool[Submarine] dict)
		{
			Submarine[] deadSubs = dict.byKey.filter!(s => s.dead).array;
			foreach (Submarine sub; deadSubs)
				dict.remove(sub);
		}

		clearDeadSubs(m_civilianBots);
		clearDeadSubs(m_easyBots);
		clearDeadSubs(m_mediumBots);

		// Despawn bots when players are long gone. Saves electricity and resets
		// difficulty.
		if (m_simulator.getConnectedPlayers())
			m_lastSeenPlayer = m_simulator.worldTime;
		else if (m_simulator.worldTime - m_lastSeenPlayer > DESPAWN_IDLE_INTERVAL)
		{
			// we don't run this code every frame, so we update m_lastSeenPlayer
			m_lastSeenPlayer = m_simulator.worldTime;
			Submarine[] subsToKill;
			foreach (Submarine sub; m_easyBots.byKey)
				subsToKill ~= sub;
			foreach (Submarine sub; m_mediumBots.byKey)
				subsToKill ~= sub;
			foreach (Submarine sub; m_simulator.vessels.alivePlayerSubmarines)
			{
				subsToKill ~= sub;
			}
			foreach (Submarine sub; subsToKill)
			{
				trace("Killing submarine because of player inactivily: ", sub);
				sub.kill("No players", null);
			}
			m_easyBots.clear();
			m_mediumBots.clear();
		}

		// give new destinations to bots that have arrived
		foreach (AICrewTemp crewTemp; m_simulator.bots.captains)
		{
			AICrew crew = cast(AICrew) crewTemp;
			assert(crew);
			if (crew.goal is null || crew.goal.status == GoalStatus.succeeded)
			{
				crew.goal = new SwimToDestinationGoal(crew,
					getDistantPos(crew.submarine.transform.wposition));
			}
		}
		// spawn animals if necessary
		void placeAnimal(string species, string name)
		{
			info("spawning ", species);
			Animal animal = Globals.entityDb.getAnimalFactory(species).build(name);
			vec2d spawnPos;
			double spawnRot;
			getRandomSpawn(spawnPos, spawnRot);
			animal.transform.position = spawnPos;
			animal.transform.rotation = spawnRot;
			animal.destination = getDistantPos(spawnPos);
			animal.register(m_simulator);
		}

		int whalesToSpawn = 1 - m_simulator.animals.entities.filter!(
			a => a.species == "humpback whale").walkLength.to!int;
		while (whalesToSpawn-- > 0)
			placeAnimal("humpback whale", "Ahmed");

		int orcasToSpawn = 1 - m_simulator.animals.entities.filter!(
			a => a.species == "orca").walkLength.to!int;
		while (orcasToSpawn-- > 0)
			placeAnimal("orca", "Kutta");

		int minkesToSpawn = 1 - m_simulator.animals.entities.filter!(
			a => a.species == "minke whale").walkLength.to!int;
		while (minkesToSpawn-- > 0)
			placeAnimal("minke whale", "Tanya");

		int mullowaysToSpawn = 2 - m_simulator.animals.entities.filter!(
			a => a.species == "mulloway").walkLength.to!int;
		while (mullowaysToSpawn-- > 0)
			placeAnimal("mulloway", "mulloway");

		int musicToSpawn = 1 - m_simulator.animals.entities.filter!(
			a => a.species == "jukebox whale").walkLength.to!int;
		while (musicToSpawn-- > 0)
			placeAnimal("jukebox whale", "Texas Red");

		// Notify players about new player spawns
		if (m_newPlayers && !m_singlePlayer)
		{
			auto unixTime = longUnixTime();
			foreach (Player newPlayer; m_newPlayers)
			{
				ChatMessageRes msg = ChatMessageRes(ChatMessage(unixTime,
					ChatMessageType.scenarioNotice,
					"Player " ~ newPlayer.name ~ " has joined in a new submarine"));
				// broadcast to all alive players
				foreach (Submarine sub; simulator.vessels.alivePlayerSubmarines)
				{
					if (sub.player is newPlayer)
						continue;
					PlayerConnection pcon = sub.player.connection;
					if (pcon)
						pcon.sendMessage(cast(immutable) msg);
				}
			}
			m_newPlayers.length = 0;
		}
	}

	/// make sure each player with a submarine in this simulator has a reload circle
	private void synchronizeReloadCircles()
	{
		foreach (Submarine sub; simulator.vessels.submarines)
		{
			if (sub.player)
			{
				if (!sub.dead)
					ensureReloadCircleForPlayer(sub.player);
				else
					m_playerReloadCircles.remove(sub.player);
			}
		}
	}

	private ReloadCircle generateReloadCirclePos(Submarine sub)
	{
		return ReloadCircle(getDistantPos(sub.transform.wposition));
	}

	private vec2d getDistantPos(vec2d from)
	{
		double dist = 0.0;
		vec2d res;
		int attempts = 32;
		while (dist <= 0.8 * m_nextRadius && attempts-- > 0)
		{
			res = m_nextCenter + rotateVector(
				vec2d(0, m_nextRadius * (0.65 + 0.3 * uniform01)),
				uniform(0, 2 * PI));
			dist = (from - res).length;
		}
		if (attempts <= 0)
			warning("getDistantPos loop too many iterations");
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
		long unixTime = longUnixTime();
		size_t combatBoutCount = m_easyBots.length + m_mediumBots.length;
		foreach (playerRcPair; m_playerReloadCircles.byKeyValue)
		{
			Player p = playerRcPair.key;
			ReloadCircle rc = playerRcPair.value;
			Submarine s = p.submarine;
			if (RELOAD_CIRCLE_RADIUS >= (s.transform.wposition - rc.center).length)
			{
				reloadSubmarine(p, s, combatBoutCount == 0);
				triggeredPlayers ~= p;
			}
		}
		foreach (Player p; triggeredPlayers)
		{
			m_playerReloadCircles.remove(p);
			ensureReloadCircleForPlayer(p);
			PlayerConnection pcon = p.connection;
			if (pcon && pcon.simulatorFlow)
			{
				MapOverlayUpdateRes mapBcst;
				ScenarioGoalUpdateRes goalBcst;
				ChatMessageRes textBcst;
				generateBriefing(p, mapBcst.mapElements, goalBcst.goals,
					textBcst.message);
				textBcst.message = ChatMessage(unixTime,
					ChatMessageType.scenarioNotice,
					"Weapon racks reloaded. New reload point allocated.");
				pcon.sendMessage(cast(immutable) mapBcst);
				pcon.sendMessage(cast(immutable) textBcst);
			}
		}
	}

	private void reloadSubmarine(Player p, Submarine s, bool noBots)
	{
		PlayerConnection pcon = p.connection;
		foreach (AmmoRoom room; s.ammoRoomRange)
		{
			int maxWeaponsToLoad =
				room.prototype.roomType == TubeType.standard ?
				TORPS_TO_RELOAD : DECOYS_TO_RELOAD;
			if (noBots)
				maxWeaponsToLoad = int.max;
			int weaponsToLoad = min(maxWeaponsToLoad, room.capacity - room.weaponCount);
			if (weaponsToLoad > 0)
			{
				string[] allowedWeapons = room.prototype.allowedWeaponSet.keys;
				while (weaponsToLoad-- > 0)
				{
					// select random allowed weapon to put in the room
					string weaponName = allowedWeapons[
						uniform(0, allowedWeapons.length)];
					room.putWeapon(weaponName);
				}
				// send room update if possible
				if (pcon && pcon.simulatorFlow)
				{
					pcon.sendMessage(cast(immutable)
						AmmoRoomStateUpdateRes(room.fullState));
				}
			}
		}
	}

	override ShouldSimTerminate onAfterSimulation(usecs_t simTimePassed)
	{
		synchronizeReloadCircles();
		triggerReloadCircles();
		// check if it's time for transition
		if (m_simulator.worldTime >= m_nextTransitionTime)
		{
			if (m_inTransition)
			{
				m_currentCenter = m_nextCenter;
				m_currentRadius = m_nextRadius;
				m_nextTransitionTime = m_simulator.worldTime + STABLE_TIME;
				info("Scenario arena transition has finished: ", m_simulator.worldTime);
			}
			else
			{
				m_nextRadius = DEFAULT_RADIUS + PER_PLAYER_EXPANSION *
					max(0, m_simulator.vessels.alivePlayerSubmarines.walkLength.to!int - 1);
				m_nextCenter = m_currentCenter + rotateVector(
					0.5 * vec2d(0, m_nextRadius),
					uniform(0, 2 * PI));
				usecs_t transitionTime = cast(usecs_t)
					(m_nextRadius / ESTIMATE_SPD) * 1000_000L;
				m_nextTransitionTime = m_simulator.worldTime + transitionTime;
				info("Scenario arena transition has started: ", m_simulator.worldTime);
				// regenerate reload circles
				m_playerReloadCircles.clear();
				synchronizeReloadCircles();
			}
			m_inTransition = !m_inTransition;
			// send message(s) to active players
			foreach (Submarine sub; simulator.vessels.submarines)
			{
				if (sub.player && !sub.dead)
				{
					MapOverlayUpdateRes mapBcst;
					ScenarioGoalUpdateRes goalBcst;
					ChatMessageRes textBcst;
					generateBriefing(sub.player, mapBcst.mapElements, goalBcst.goals,
						textBcst.message);
					PlayerConnection pcon = sub.player.connection;
					if (pcon)
					{
						pcon.sendMessage(cast(immutable) textBcst);
						pcon.sendMessage(cast(immutable) mapBcst);
					}
				}
			}
			// give new destinations to bots
			foreach (AICrewTemp crwTemp; m_simulator.bots.captains)
			{
				AICrew crew = cast(AICrew) crwTemp;
				assert(crew);
				crew.goal = new SwimToDestinationGoal(crew,
					getDistantPos(crew.submarine.transform.wposition));
			}
			foreach (Animal an; m_simulator.animals.entities)
				an.destination = getDistantPos(an.transform.wposition);
		}
		if (m_singlePlayer && m_playerSub.dead)
			return ShouldSimTerminate.yes;
		return ShouldSimTerminate.no;
	}

	override void generateBriefing(Player player,
		out MapElement[] mapOverlayEls, out ScenarioGoal[] goals,
		out ChatMessage briefing)
	{
		long unixTime = longUnixTime();
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
				ChatMessageType.scenarioNotice,
				"New arena position, hurry to the dark-blue circle! " ~
				"Time until forced navigation: " ~
				((m_nextTransitionTime - m_simulator.worldTime) / 1000_000).
					to!string ~ " seconds.");
		}
		else
		{
			briefing = ChatMessage(
				unixTime,
				ChatMessageType.scenarioNotice,
				"Navigation limited to dark-blue circle!");
		}
		if (!m_singlePlayer)
		{
			// say, how many players are online
			int playerCount = simulator.vessels.alivePlayerSubmarines.walkLength.to!int;
			briefing.message ~= " Total players on arena: " ~ (playerCount - 1).to!string;
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

	private vec2d getRandSubSpawnPos()
	{
		// try to find position that is far away from other alive submarines
		int attempts = 16;
		vec2d bestCandidate;
		double bestMinDistance;
		enum double passMinDist = 4500.0;
		for (int i = 0; i < attempts; i++)
		{
			// favor map edge
			vec2d pos = m_nextCenter + rotateVector(
				vec2d(0, m_nextRadius * (0.6 + 0.33 * uniform01)),
				uniform(0, 2 * PI));
			if (m_simulator.vessels.aliveSubmarines.empty)
				return pos;
			double minDist = m_simulator.vessels.aliveSubmarines.map!(
				s => (s.transform.wposition - pos).length).minElement;
			if (minDist >= passMinDist)
				return pos;
			if (i == 0 || minDist > bestMinDistance)
			{
				bestMinDistance = minDist;
				bestCandidate = pos;
			}
		}
		warning("getRandSubSpawnPos loop too many iterations");
		return bestCandidate;
	}

	private void getRandomSpawn(out vec2d position, out double rotation)
	{
		position = getRandSubSpawnPos();
		rotation = uniform(0.0f, 2 * PI);
	}

	override void selectPlayerSpawnPosition(Player p, out vec2d position, out double rotation)
	{
		if (m_singlePlayer)
		{
			m_playerSub = p.submarine;
			assert(m_playerSub);
		}
		else
		{
			m_newPlayers ~= p;
		}
		getRandomSpawn(position, rotation);
	}
}
