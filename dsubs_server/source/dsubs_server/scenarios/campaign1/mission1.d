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
module dsubs_server.scenarios.campaign1.mission1;

import std.algorithm;
import std.random: randomShuffle;

import dsubs_common.api.messages;
import dsubs_common.api.entities;
import dsubs_common.math.angles;

import dsubs_sound.soundsource;

import dsubs_server.common;
import dsubs_server.bots;
import dsubs_server.ai.captain;
import dsubs_server.acoustics;
import dsubs_server.animal;
import dsubs_server.vessel;
import dsubs_server.submarine;
import dsubs_server.scenario;
import dsubs_server.player: SideOfConflict;
import dsubs_server.simulator;



final class Cmp1Mission1: SinglePlayerScenario
{
	static AvailableScenarioConstants getConstants()
	{
		AvailableScenarioConstants constants;
		constants.name = "Whale's Health";
		constants.shortDescription = "Coast Guard duties and mammal woes";
		constants.fullDescription =
`
FSC-94/O-65        SUBMARINE SQUADRON TWO

Patrol order to CWS RUSTBUCKET (SS13).

From:       The Commander-in-Chief, Commonwealth Fleet.
To:         The Commander Submarine RUSTBUCKET.
Via:        The Commander Submarines, FIRST FLEET.

Subject:    CWS RUSTBUCKET (SS08) - Partrol order.

	Situation:  Moderate civilian vessel traffic. No military vessels
in the area. Dispersed whales, vocalize lively.

	Objective 1:  Marine Life Department has requested our assistance with mammal
health problem. Three humpback whales, LIAM, GRACE and SAMUEL
are suspected to be infected with rabies. The virus makes poor animals scream from
agonizing pain, frightening the crew of nearby vessels and causing discontent.
First Fleet staff was eager to put the poor souls out of their misery, while
simultaniously testing the newest Minoga-class torpedo.
	Commander, you are only to kill the wailing whales. Animals that are
not screaming are to be considered healthy and not be touched.
	Keep in mind that a whale is a small target that requires
extra accuracy (straight run pattern) and minimal torpedo speed (21) to hit.
Use active sonar guidance mode.

    Objective 2:  Crew of the civilian tanker HIPPO is reported to be banging
'LIQUID DRUM AND BASS' at whopping 100 dB. While the acoustic surveillance
officers appreciate the joke, the crew needs to be reminded of the restrictions
on noise pollution, imposed in our territorial waters. Get in range of 300m
from the HIPPO and ping at max power. They are not the only jokers.

    Operations mode:  You are to conduct your patrol duty according to peace time
regulations. You are NOT TO USE your main active sonar at ranges less than
500m from a whale (even a sick one), as dictated by Marine Life Preservation Act.

    Good luck, Commander!
`;
		constants.allowedEntities = EntityDbShort(
			["Stork"], ["Seven-blade screw"],
			["Minoga", "Decoy(active)", "Decoy(passive)"]);
		return constants;
	}

	this(Simulator sim)
	{
		super(sim, ChatMessage(longUnixTime(), ChatMessageType.scenarioNotice,
			"Welcome to the campaign, captain"));
		initializeWhales();
		initializeTraders();
	}

	Animal[] whales;
	enum double WHALE_SPAWN_RADIUS = 400.0;
	enum int SICK_WHALE_COUNT = 2;
	vec2d[] whaleSpawnPoints = [
		vec2d(1500, 2000),
		vec2d(-4500, 1000),
		vec2d(-500, 8000)
	];
	string[] whaleNames = [
		"Liam",
		"Grace",
		"Samuel"
	];

	enum double THEATER_RADIUS = 12000.0;

	private vec2d getRandomPosInTheatre() const
	{
		return randomPointInCircle(vec2d(0.0, 0.0), THEATER_RADIUS);
	}

	private Animal spawnWhale(string name, vec2d center, bool sick)
	{
		Animal animal = Globals.entityDb.getAnimalFactory("humpback whale").
			build((sick ? "sick ": "") ~ name);
		vec2d randomPos = randomPointInCircle(center, WHALE_SPAWN_RADIUS);
		animal.transform.position = randomPos;
		animal.transform.rotation = uniform(0, 2 * PI);
		animal.destination = getRandomPosInTheatre();
		// increase singing frequency, because whales in arenas sing rarely
		animal.soundTimings.meanSongPause = cast(usecs_t) 1 * 60 * 1000_000;
		animal.soundTimings.songPauseVariance = cast(usecs_t) 30 * 1000_000;
		// sick whale has different sounds
		if (sick)
		{
			animal.soundTimings.meanSongPause /= 2;
			animal.soundTimings.songPauseVariance /= 2;
			animal.randomSounds = [
				new PrerecordedSoundConfig(
					"../dsubs_sound/scenario_sounds/man_screaming1.wav",
					9.0f, 95.0f),
				new PrerecordedSoundConfig(
					"../dsubs_sound/scenario_sounds/man_screaming2.wav",
					9.0f, 95.0f),
				new PrerecordedSoundConfig(
					"../dsubs_sound/scenario_sounds/man_screaming3.wav",
					9.0f, 95.0f),
			];
		}
		animal.register(m_simulator);
		return animal;
	}

	private void initializeWhales()
	{
		randomShuffle(whaleNames);
		randomShuffle(whaleSpawnPoints);
		for (size_t i = 0; i < whaleNames.length; i++)
		{
			bool sick = i < SICK_WHALE_COUNT;
			Animal whale = spawnWhale(whaleNames[i], whaleSpawnPoints[i], sick);
			whales ~= whale;
			if (sick)
			{
				// kill goal
				SimpleGoal killWhaleGoal = new SimpleGoal(
					"Kill sick " ~ whaleNames[i],
					"Put the screaming mammal out of it's misery.");
				addVisibleGoal(killWhaleGoal);
				ScenarioTrigger killTrigger = new ScenarioTrigger(
					new DeadCondition(((w) => { return w; })(whale)),
					((g) => { g.markSuccess(); })(killWhaleGoal) );
				addTrigger(killTrigger);
			}
			else
			{
				SimpleGoal noHealthyKill = new SimpleGoal("Don't kill " ~ whaleNames[i],
					"One of the whales is healthy, it must survive",
					"You shouldn't have killed " ~ whaleNames[i] ~ " ((");
				noHealthyKill.requiredForVictory = false;
				addVisibleGoal(noHealthyKill);
				ScenarioTrigger killTrigger = new ScenarioTrigger(
					new DeadCondition(((w) => { return w; })(whale)),
					((g) => { g.markFailed(); })(noHealthyKill) );
				addTrigger(killTrigger);
			}
			m_syncState.mapElements.addElement("whale" ~ i.to!string,
				MapElement.circle(
					MapCircle(
						whaleSpawnPoints[i], WHALE_SPAWN_RADIUS, 3),
					COLOR_WAYPOINT));
			m_syncState.mapElements.addElement("whaleLbl" ~ i.to!string,
				MapElement.text(
					MapText(
						whaleSpawnPoints[i], 12),
					COLOR_WAYPOINT,
					"Whale " ~ (i + 1).to!string));
		}

		SimpleGoal doNotPingWhalesGoal = new SimpleGoal(
			"Sonar discipline",
			"Do not emit active pings at range less than 500m from " ~
			"any whale",
			"The pain you've caused to whale ears is immeasurable and " ~
			"his day is ruined.");
		doNotPingWhalesGoal.requiredForVictory = false;
		addVisibleGoal(doNotPingWhalesGoal);
		foreach (Animal whale; whales)
		{
			ScenarioTrigger pingTooCLoseTrigger = new ScenarioTrigger(
				new SubPingsDistanceCondition(
					{ return m_playerSub; }, simulator,
					((w) => {
						if (!w.dead)
							return w.transform;
						else
							return null;
					})(whale),
					Comparator.less, 500.0),
				{ doNotPingWhalesGoal.markFailed(); });
			addTrigger(pingTooCLoseTrigger);
		}
	}

	SideOfConflict civilians;
	Submarine[] traders;
	Submarine musicTrader;
	SimpleGoal forbidTraderKillGoal;
	SimpleGoal pingCloseToMusicGoal;

	private struct SpawnAndDest
	{
		vec2d spawn;
		vec2d dest;
	}

	SpawnAndDest[] traderSpawnPoints = [
		SpawnAndDest(vec2d(4500, -1000), vec2d(-30000, 60000)),
		SpawnAndDest(vec2d(7500, -4000), vec2d(-20000, 80000)),
		SpawnAndDest(vec2d(2500, 11000), vec2d(15000, -60000))
	];
	SpawnAndDest musicTraderSpawn =
		SpawnAndDest(vec2d(5500, -2000), vec2d(-15000, 100000));

	private Submarine spawnTrader(SpawnAndDest spawn, bool musical)
	{
		string crewName = musical ? "Hippo crew" : null;
		AICrew crew = new AICrew(BOT_DIFFICULTY.easy, crewName);
		crew.side = civilians;
		SpawnReq req = SpawnReq("Bot trader", "Civilian three-blade screw");
		Submarine botSub = Globals.entityDb.buildSubFromLoadout(req, crew);
		botSub.transform.position = spawn.spawn;
		botSub.transform.rotation = courseAngle(spawn.dest - spawn.spawn);
		crew.goal = new SwimToDestinationGoal(crew, spawn.dest);
		m_simulator.bots.registerEntity(crew);
		botSub.register(m_simulator);

		if (musical)
		{
			// we add periodic music controller
			Jukebox jukebox = new Jukebox(botSub, botSub.transform);
			jukebox.soundTimings = JukeboxSoundTimings(
				cast(usecs_t) 60 * 1000_000L,
				cast(usecs_t) 20 * 1000_000L
			);
			jukebox.randomSounds = [
				new PrerecordedSoundConfig(
						"../dsubs_sound/scenario_sounds/Monrroe - Out of Time (feat. Zara Kershaw).wav",
					10.0f, 105.0f),
				new PrerecordedSoundConfig(
						"../dsubs_sound/scenario_sounds/Epiphany-TwoThirds.wav",
					10.0f, 105.0f),
			];
			jukebox.setSimulator(m_simulator);
			m_simulator.onSimulationPassEnd += (sim, worldTime) {
				if (!botSub.dead &&
					pingCloseToMusicGoal.status == ScenarioGoalStatus.unreached)
				{
					jukebox.onSimUpdate();
				}
			};

			// add trigger to stop music when we ping nearby
			ScenarioTrigger pingCloseTrigger = new ScenarioTrigger(
				new SubPingsDistanceCondition(
					{ return m_playerSub; }, simulator,
					{ return botSub.transform; },
					Comparator.less, 300.0),
				{
					pingCloseToMusicGoal.markSuccess();
					jukebox.shutdown();
				}
			);
			addTrigger(pingCloseTrigger);
		}

		// kill forbid trigger
		ScenarioTrigger dontKillTrigger = new ScenarioTrigger(
			new DeadCondition({ return botSub; }),
			{ forbidTraderKillGoal.markFailed(); });
		addTrigger(dontKillTrigger);

		return botSub;
	}

	private void initializeTraders()
	{
		civilians = new SideOfConflict("Civilians", true);

		forbidTraderKillGoal = new SimpleGoal("Peace time",
			"No civilian vessels must be damaged",
			"Innocent lives were lost due to your sloppy aim");
		forbidTraderKillGoal.requiredForVictory = false;
		addVisibleGoal(forbidTraderKillGoal);

		pingCloseToMusicGoal = new SimpleGoal("Frighten the Hippo",
			"Ping while being closer than 300m from the civilian ship that " ~
			"is banging loud music");
		addVisibleGoal(pingCloseToMusicGoal);

		foreach (SpawnAndDest snd; traderSpawnPoints)
		{
			Submarine trader = spawnTrader(snd, false);
			traders ~= trader;
		}
		musicTrader = spawnTrader(musicTraderSpawn, true);
	}
}


