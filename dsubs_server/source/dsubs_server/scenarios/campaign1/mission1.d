module dsubs_server.scenarios.campaign1.mission1;

import std.algorithm;
import std.random: randomShuffle;

import dsubs_common.api.messages;
import dsubs_common.api.entities;
import dsubs_common.math.angles;

import dsubs_server.common;
import dsubs_server.bots;
import dsubs_server.ai.captain;
import dsubs_server.animal;
import dsubs_server.vessel;
import dsubs_server.submarine;
import dsubs_server.scenario;
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

    Objective 2:  Crew of the civilian tanker HIPPO is reported to be banging
'LIQUID DRUM AND BASS' at whopping 140 dB. While the acoustic surveillance
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
	}

	Animal[] whales;
	enum double WHALE_SPAWN_RADIUS = 400.0;
	enum int SICK_WHALE_COUNT = 2;
	vec2d[] whaleSpawnPoints = [
		vec2d(1500, 2000),
		vec2d(-2500, 1000),
		vec2d(-500, 5000)
	];
	string[] whaleNames = [
		"Liam",
		"Grace",
		"Samuel"
	];

	enum double THEATER_RADIUS = 10000.0;

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
		// TODO: add sick screams
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
					((w) => { return w.transform; })(whale),
					Comparator.less, 500.0),
				{ doNotPingWhalesGoal.markFailed(); });
			addTrigger(pingTooCLoseTrigger);
		}
	}
}


