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
		constants.name = "Whale health inspection";
		constants.shortDescription = "Routine marine mammal health inspection, coastal partol";
		constants.fullDescription =
`
.`;
		constants.allowedEntities = EntityDbShort(
			["Lima"], ["Five-blade Lima screw"], ["Minoga"]);
		return constants;
	}

	this(Simulator sim)
	{
		super(sim, ChatMessage(longUnixTime(), ChatMessageType.scenarioNotice,
			"Welcome to torpedo tutorial"));
	}
}


