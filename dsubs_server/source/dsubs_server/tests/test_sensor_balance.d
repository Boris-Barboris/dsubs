module dsubs_server.tests.test_sensor_balance;

import std.stdio;

import dsubs_common.api.messages;
import dsubs_common.math;

import dsubs_sound.hydrophone;

import dsubs_server.common;
import dsubs_server.entitydb;
import dsubs_server.submarine;
import dsubs_server.simulator;
import dsubs_server.propulsion;

import dsubs_server.tests.common;


double getSpawnReqMaxSpeed(SpawnReq req)
{
	Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
	return speedForThrottle(s.rigidBody.hydroModel, cast(BasicPropulsor) s.propulsor);
}


unittest
{
	Globals.buildForTests();
	scope(exit) Globals.resetForTests();
	SpawnReq req = SpawnReq("Bot trader", "Civilian three-blade screw");
	double maxSpd = getSpawnReqMaxSpeed(req);
	trace("max Bot trader speed: ", maxSpd);
	PropulsorFactory pf = Globals.entityDb.getPropulsorFactory("Civilian three-blade screw");
	hydrophoneVsPropellerBalancingPlot(
		Globals.sctx.queue(0),
		"stork_vs_bot_trader",
		Globals.entityDb.getSubmarineFactory("Stork").hprots[0].hydroProto,
		pf.soundPrototype,
		pf.shaftRotFreq / maxSpd,
		1.0f,
		maxSpd,
		15000.0f,
		17.0f);
}


unittest
{
	Globals.buildForTests();
	scope(exit) Globals.resetForTests();
	SpawnReq req = SpawnReq("Stork", "Seven-blade screw");
	double maxSpd = getSpawnReqMaxSpeed(req);
	trace("max Stork speed: ", maxSpd);
	PropulsorFactory pf = Globals.entityDb.getPropulsorFactory("Seven-blade screw");
	hydrophoneVsPropellerBalancingPlot(
		Globals.sctx.queue(0),
		"stork_vs_stork",
		Globals.entityDb.getSubmarineFactory("Stork").hprots[0].hydroProto,
		pf.soundPrototype,
		pf.shaftRotFreq / maxSpd,
		1.0f,
		maxSpd,
		15000.0f,
		17.0f);
}


unittest
{
	Globals.buildForTests();
	scope(exit) Globals.resetForTests();
	SpawnReq req = SpawnReq("Stork", "Seven-blade screw");
	double maxSpd = getSpawnReqMaxSpeed(req);
	trace("max Stork speed: ", maxSpd);
	PropulsorFactory pf = Globals.entityDb.getPropulsorFactory("Seven-blade screw");
	hydrophoneVsPropellerBalancingPlot(
		Globals.sctx.queue(0),
		"lima_vs_stork",
		Globals.entityDb.getSubmarineFactory("Lima").hprots[0].hydroProto,
		pf.soundPrototype,
		pf.shaftRotFreq / maxSpd,
		1.0f,
		maxSpd,
		15000.0f,
		17.0f);
}


unittest
{
	Globals.buildForTests();
	scope(exit) Globals.resetForTests();
	PropulsorFactory pf = (
		cast(PassiveDecoyFactory) Globals.entityDb.getWeaponFactory("Decoy(passive)")).propFactory;
	hydrophoneVsPropellerBalancingPlot(
		Globals.sctx.queue(0),
		"stork_vs_passive_decoy",
		Globals.entityDb.getSubmarineFactory("Stork").hprots[0].hydroProto,
		pf.soundPrototype,
		pf.shaftRotFreq / 2.0f,
		1.0f,
		2.0f,
		15000.0f,
		17.0f);
}

