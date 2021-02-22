module dsubs_server.scenarios.campaign1.mission1;

import std.algorithm;

import dsubs_common.api.messages;
import dsubs_common.api.entities;
import dsubs_common.math.angles;

import dsubs_server.common;
import dsubs_server.bots;
import dsubs_server.ai.captain;
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
		constants.shortDescription = "Coast Guard duties and marine mammal health";
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
500m from a whale (even sick one), as dictated by Marine Life Preservation Act.

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
			"End their suffering for good"));
		initializeWhales();
	}

	Animal[] whales;
	enum double WHALE_SPAWN_RADIUS = 400.0;
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

	private void initializeWhales()
	{

	}
}


