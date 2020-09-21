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
		constants.shortDescription = "Coast Guard duties and marine mammal health inspection";
		constants.fullDescription =
`
                         CLASSIFIED

FSC-94/O-65        SUBMARINE SQUADRON SIX

Patrol order to CWS RUSTBUCKET (SS13).

From:       The Commander in Chief, Commonwealth Fleet.
To:         The Commander Submarine RUSTBUCKET.
Via:        The Commander Submarines, FIRST FLEET.

Subject:    CWS RUSTBUCKET (SS13) - Partrol order.

    Situation:  Moderate civilian vessel traffic. No military-capable vessels
in the area. Dispersed single whales, vocalize lively. Sea state gentle.

    Objective 1:  Conduct routine civilian traffic monitoring in the
Simmons bay. Perform selective boarding inspection, if directed by
Coast Guard and Customs operations center.

    Objective 2:  Marine Life Department has requested our assistance with mammal
health monitoring routines. Three local humpback whales, LIAM, GRACE and SAMUEL
must be inspected. Annuall rabies wave that makes poor animals scream from
virus-induced pain, is kept in check by rigorous termination of infected
individuals. First Fleet staff was eager to help due to torpedo-related
opportunities, that are opened by the necessity of large mammal disposal.

    Operations mode:  You are to conduct your patrol duty according to peace time
regulations. Attack torpedoes are to be fired in anger in self-defense or
maritime border violation situations, after sufficient number of communication
attempts. Active sonar ping at close (less than 500m) distance is
considered a sufficient warning for the inspected ship to halt.
You are NOT TO USE your main active sonar at ranges less than 500m from a
whale, as prescribed by Marine Life Perseverance Act.

    Signalling: Mainline bi-directional acoustic communications will be maintained
by station OX-4. Reserve broadcast-only acoustic station OX-6.

    Good luck, Captain!
`;
		constants.allowedEntities = EntityDbShort(
			["Stork"], ["Seven-blade screw"],
			["Minoga", "Decoy(active)", "Decoy(passive)"]);
		return constants;
	}

	this(Simulator sim)
	{
		super(sim, ChatMessage(longUnixTime(), ChatMessageType.scenarioNotice,
			"Welcome to torpedo tutorial"));
	}
}


