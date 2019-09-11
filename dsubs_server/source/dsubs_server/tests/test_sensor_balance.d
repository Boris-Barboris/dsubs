module dsubs_server.tests.test_sensor_balance;

import std.stdio;

import dsubs_common.api.protocols.backend;
import dsubs_common.math;

import dsubs_sound.hydrophone;

import dsubs_server.common;
import dsubs_server.entitydb;
import dsubs_server.submarine;
import dsubs_server.propulsion;

import dsubs_server.tests.common;


double getSpawnReqMaxSpeed(SpawnReq req)
{
	Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
	return maxSpeed(s.rigidBody.hydroModel, cast(BasicPropulsor) s.propulsor);
}

unittest
{
	SpawnReq req = SpawnReq("Bot trader", "Civilian three-blade screw");
	double maxSpd = getSpawnReqMaxSpeed(req);
	trace("max Bot trader speed: ", maxSpd);
	PropulsorFactory pf = Globals.entityDb.getPropulsorFactory("Civilian three-blade screw");
	hydrophoneVsPropellerBalancingPlot(
		Globals.sctx.queue(0),
		"stork_vs_bot_trader",
		Globals.entityDb.getSubmarineFactory("Stork").hprots[0],
		pf.soundPrototype,
		pf.shaftRotFreq / maxSpd,
		1.0f,
		maxSpd,
		15000.0f,
		17.0f);
}