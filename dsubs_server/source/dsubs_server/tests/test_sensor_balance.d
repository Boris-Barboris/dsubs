module dsubs_server.tests.test_sensor_balance;

import std.file;
import std.stdio;

import dsubs_common.api.messages;
import dsubs_common.math;

import dsubs_sound.common: GLOBAL_SRATE;
import dsubs_sound.units;
import dsubs_sound.soundsource: calcPropellerIntensity;
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
	return speedForThrottle(s.rigidBody.hydroModel, s.propulsors.length,
		cast(BasicPropulsor) s.propulsors[0]);
}

void writePropellerNoiseVsSpeedCsv(Submarine v, string testName, int minFreq, int maxFreq,
	int numSpeedPoints = 40, float dissMod = 4.0f)
{
	mkdirRecurse("test_data/propulsor_noise");
	File* f = new File("test_data/propulsor_noise/" ~ testName ~
		"_" ~ v.prototypeName ~ "_" ~ v.propulsors[0].prototypeName ~ ".csv", "w");
	scope(exit) f.detach();
	f.writeln("speed,noise_db");
	float minSpeed = 0.1f;
	float maxSpeed = speedForThrottle(v.rigidBody.hydroModel, v.propulsors.length,
		cast(BasicPropulsor) v.propulsors[0], 1.0f);
	float dspeed = (maxSpeed - minSpeed) / (numSpeedPoints - 1);
	float speed = minSpeed;
	for (int i = 0; i < numSpeedPoints; i++)
	{
		float throttle = throttleForSpeed(v, speed);
		float shaftFreq = (cast(BasicPropulsor) v.propulsors[0]).shaftFreq(throttle);
		trace("speed: ", speed, ", throttle: ", throttle);
		Intensity bandSum = calcPropellerIntensity(
			(cast(BasicPropulsor) v.propulsors[0]).sound,
			Globals.sctx.queue(0), 1000.0f, speed, shaftFreq, PI_2,
			minFreq, maxFreq, dissMod);
		bandSum.val *= v.propulsors.length;
		f.writefln!"%f,%f"(speed, bandSum.toDb.val);
		speed += dspeed;
	}
}


void writePropellerNoiseVsSpeedCsv(Torpedo v, string testName, int minFreq, int maxFreq,
	int numSpeedPoints = 40, float dissMod = 4.0f)
{
	mkdirRecurse("test_data/propulsor_noise");
	File* f = new File("test_data/propulsor_noise/" ~ testName ~
		"_" ~ v.prototypeName ~ "_" ~ v.propulsors[0].prototypeName ~ ".csv", "w");
	scope(exit) f.detach();
	f.writeln("speed,noise_db");
	// min speed should be taken from min march speed in guidance parameters
	const WeaponFactory wf = Globals.entityDb.getWeaponFactory(v.prototypeName);
	float minSpeed = wf.marchSpeedRange.min;
	float maxSpeed = wf.activeSpeedRange.max;
	float dspeed = (maxSpeed - minSpeed) / (numSpeedPoints - 1);
	if (dspeed == 0.0f)
		numSpeedPoints = 1;
	float speed = minSpeed;
	for (int i = 0; i < numSpeedPoints; i++)
	{
		float throttle = throttleForSpeed(v, speed);
		float shaftFreq = (cast(BasicPropulsor) v.propulsors[0]).shaftFreq(throttle);
		trace("speed: ", speed, ", throttle: ", throttle);
		Intensity bandSum = calcPropellerIntensity(
			(cast(BasicPropulsor) v.propulsors[0]).sound,
			Globals.sctx.queue(0), 1000.0f, speed, shaftFreq, PI_2,
			minFreq, maxFreq, dissMod);

		f.writefln!"%f,%f"(speed, bandSum.toDb.val);
		speed += dspeed;
	}
}


void writePropellerNoiseVsSpeedCsv(StaticDecoy v, string testName, int minFreq, int maxFreq,
	float dissMod = 4.0f)
{
	mkdirRecurse("test_data/propulsor_noise");
	File* f = new File("test_data/propulsor_noise/" ~ testName ~
		"_" ~ v.prototypeName ~ "_" ~ v.propulsors[0].prototypeName ~ ".csv", "w");
	scope(exit) f.detach();
	f.writeln("speed,noise_db");
	// min speed should be taken from min march speed in guidance parameters
	const WeaponFactory wf = Globals.entityDb.getWeaponFactory(v.prototypeName);
	float throttle = 0.9f;
	float shaftFreq = (cast(BasicPropulsor) v.propulsors[0]).shaftFreq(throttle);
	Intensity bandSum = calcPropellerIntensity(
		(cast(BasicPropulsor) v.propulsors[0]).sound,
		Globals.sctx.queue(0), 1000.0f, 0.0f, shaftFreq, PI_2,
		minFreq, maxFreq, dissMod);

	f.writefln!"%f,%f"(0.0f, bandSum.toDb.val);
}

/*

unittest
{
	// draw propulsor noise levels
	Globals.buildForTests();
	scope(exit) Globals.resetForTests();
	SpawnReq req = SpawnReq("Stork", "Seven-blade screw");
	Submarine sub = Globals.entityDb.buildSubFromLoadout(req, null);
	writePropellerNoiseVsSpeedCsv(sub, "sub_propellers", 250, GLOBAL_SRATE / 2);
	req = SpawnReq("Stork", "Stork pumpjet");
	sub = Globals.entityDb.buildSubFromLoadout(req, null);
	writePropellerNoiseVsSpeedCsv(sub, "sub_propellers", 250, GLOBAL_SRATE / 2);
	req = SpawnReq("Lima", "Five-blade Lima screw");
	sub = Globals.entityDb.buildSubFromLoadout(req, null);
	writePropellerNoiseVsSpeedCsv(sub, "sub_propellers", 250, GLOBAL_SRATE / 2);
	req = SpawnReq("Kilo", "Five-blade Kilo screw");
	sub = Globals.entityDb.buildSubFromLoadout(req, null);
	writePropellerNoiseVsSpeedCsv(sub, "sub_propellers", 250, GLOBAL_SRATE / 2);
	req = SpawnReq("November", "Five-blade November screw");
	sub = Globals.entityDb.buildSubFromLoadout(req, null);
	writePropellerNoiseVsSpeedCsv(sub, "sub_propellers", 250, GLOBAL_SRATE / 2);
	req = SpawnReq("Bot trader", "Civilian three-blade screw");
	sub = Globals.entityDb.buildSubFromLoadout(req, null);
	writePropellerNoiseVsSpeedCsv(sub, "sub_propellers", 250, GLOBAL_SRATE / 2);
}

*/

unittest
{
	// draw torpedo noise levels
	Globals.buildForTests();
	scope(exit) Globals.resetForTests();
	WeaponFactory wf = Globals.entityDb.getWeaponFactory("Minoga");
	Torpedo w = cast(Torpedo) wf.build(null, null);
	writePropellerNoiseVsSpeedCsv(w, "torpedoes", 250, GLOBAL_SRATE / 2);
	wf = Globals.entityDb.getWeaponFactory("Electra");
	w = cast(Torpedo) wf.build(null, null);
	writePropellerNoiseVsSpeedCsv(w, "torpedoes", 250, GLOBAL_SRATE / 2);
	wf = Globals.entityDb.getWeaponFactory("Tornado");
	w = cast(Torpedo) wf.build(null, null);
	writePropellerNoiseVsSpeedCsv(w, "torpedoes", 250, GLOBAL_SRATE / 2);
	wf = Globals.entityDb.getWeaponFactory("Decoy(passive)");
	StaticDecoy d = cast(StaticDecoy) wf.build(null, null);
	writePropellerNoiseVsSpeedCsv(d, "torpedoes", 250, GLOBAL_SRATE / 2);
}

/*

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

*/