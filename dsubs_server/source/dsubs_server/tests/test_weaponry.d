module dsubs_server.tests.test_weaponry;

import std.stdio;
import std.algorithm: min;

import dsubs_common.api.protocols.backend;
import dsubs_common.math;

import dsubs_server.common;
import dsubs_server.entitydb;
import dsubs_server.submarine;
import dsubs_server.propulsion;
import dsubs_server.weaponry;
import dsubs_server.torpedo;
import dsubs_sound.activesonar;

import dsubs_server.tests.common;


unittest
{
	Globals.buildForTests();
	SpawnReq req = SpawnReq("Stork", "Seven-blade screw",
		[
			AmmoRoomFullState(0, [WeaponCount("Minoga", 15)])
		]);
	Submarine s = Globals.entityDb.buildSubFromLoadout(req, null);
	s.targetCourse = s.transform.rotation;
	s.targetThrottle = 1.0f;
	s.rigidBody.kinet.vel = vec2d(0, 15);
	s.register();
	File* storkFile = writeRbodyCsvHeader("weaponry", "stork_launch_minoga", "stork");
	Globals.sim.onSimulationPassStart += captureVesselRbCsv(storkFile, s);
	Globals.sim.worldTimeLimit = 60 * cast(usecs_t)1e6;

	Torpedo launchedTorp;

	Globals.sim.onSimulationPassEnd += (usecs_t worldTime) {
		int secs = to!int(worldTime / 1000_000);
		switch (secs)
		{
			case 1:
			{
				// test unloading of unloaded
				TubeOperationResult res = s.getTube(0).processLoadRequest("");
				assert(res.tubeChanged == false);
				assert(s.getTube(0).state == TubeState.dry);
				res = s.getTube(0).processLoadRequest("Minoga");
				// start loading minoga into tube 1
				assert(res.tubeChanged && res.roomChanged);
				assert(s.getTube(0).state == TubeState.loading);
				assert(s.getTube(0).loadedWeapon == "Minoga");
				assert(s.getAmmoRoom(0).getWeaponCount("Minoga") == 14);
				return;
			}
			case 2:
			{
				assert(s.getTube(0).lastSimUpdateResult.tubeChanged == false);
				assert(s.getTube(0).state == TubeState.loading);
				assert(s.getTube(0).loadedWeapon == "Minoga");
				assert(s.getAmmoRoom(0).getWeaponCount("Minoga") == 14);
				return;
			}
			case 1 + 10:
			{
				// assert that the state has changed to loaded
				assert(s.getTube(0).lastSimUpdateResult.tubeChanged);
				assert(s.getTube(0).state == TubeState.dry);
				assert(s.getTube(0).loadedWeapon == "Minoga");
				assert(s.getAmmoRoom(0).getWeaponCount("Minoga") == 14);
				return;
			}
			case 1 + 11:
			{
				// switch desired state to open
				TubeOperationResult res = s.getTube(0).processStateRequest(TubeState.open);
				assert(res.tubeChanged && !res.roomChanged);
				assert(s.getTube(0).state == TubeState.dry);
				assert(s.getTube(0).desiredState == TubeState.open);
				return;
			}
			case 1 + 11 + 3:
			{
				assert(s.getTube(0).lastSimUpdateResult.tubeChanged == false);
				assert(s.getTube(0).state == TubeState.flooding);
				assert(s.getTube(0).desiredState == TubeState.open);
				return;
			}
			case 1 + 11 + 6:
			{
				assert(s.getTube(0).lastSimUpdateResult.tubeChanged);
				assert(s.getTube(0).state == TubeState.flooded);
				assert(s.getTube(0).desiredState == TubeState.open);
				return;
			}
			case 1 + 11 + 6 + 2:
			{
				assert(s.getTube(0).lastSimUpdateResult.tubeChanged == false);
				assert(s.getTube(0).state == TubeState.opening);
				assert(s.getTube(0).desiredState == TubeState.open);
				return;
			}
			case 1 + 11 + 6 + 3:
			{
				assert(s.getTube(0).lastSimUpdateResult.tubeChanged);
				assert(s.getTube(0).state == TubeState.open);
				assert(s.getTube(0).desiredState == TubeState.open);
				return;
			}
			case 1 + 11 + 6 + 3 + 1:
			{
				// try to launch torpedo
				WeaponParamValue[] pvs;
				WeaponParamValue pv;

				pv.type = WeaponParamType.marchCourse;
				pv.course = dgr2rad(0.0);
				pvs ~= pv;
				pv.type = WeaponParamType.activeCourse;
				pv.course = dgr2rad(0.0);
				pvs ~= pv;
				pv.type = WeaponParamType.activationRange;
				pv.range = 200.0f;
				pvs ~= pv;
				pv.type = WeaponParamType.marchSpeed;
				pv.speed = 21.0f;
				pvs ~= pv;
				pv.type = WeaponParamType.activeSpeed;
				pv.speed = 21.0f;
				pvs ~= pv;
				pv.type = WeaponParamType.searchPattern;
				pv.searchPattern = WeaponSearchPattern.snake;
				pvs ~= pv;

				LaunchTubeReq lreq = LaunchTubeReq(0, pvs);
				TubeOperationResult res = s.getTube(0).processLaunchRequest(pvs);
				assert(res.tubeChanged && !res.roomChanged);
				assert(s.getTube(0).state == TubeState.firing);
				assert(s.getTube(0).desiredState == TubeState.open);

				launchedTorp = Globals.torps.torpedoes[0];
				File* minogaFile = writeRbodyCsvHeader("weaponry", "stork_launch_minoga",
					"minoga");
				Globals.sim.onSimulationPassStart += captureVesselRbCsv(minogaFile,
					launchedTorp);
				return;
			}
			case 1 + 11 + 6 + 3 + 1 + 3:
			{
				assert(s.getTube(0).lastSimUpdateResult.tubeChanged);
				assert(s.getTube(0).state == TubeState.open);
				assert(s.getTube(0).desiredState == TubeState.open);
				// switch desired state to dry
				TubeOperationResult res = s.getTube(0).processStateRequest(TubeState.dry);
				assert(res.tubeChanged && !res.roomChanged);
				assert(s.getTube(0).state == TubeState.open);
				assert(s.getTube(0).desiredState == TubeState.dry);
				return;
			}
			case 1 + 11 + 6 + 3 + 1 + 3 + 1:
			{
				assert(s.getTube(0).lastSimUpdateResult.tubeChanged);
				assert(s.getTube(0).state == TubeState.closing);
				assert(s.getTube(0).desiredState == TubeState.dry);
				return;
			}
			case 1 + 11 + 6 + 3 + 1 + 3 + 3:
			{
				assert(s.getTube(0).lastSimUpdateResult.tubeChanged);
				assert(s.getTube(0).state == TubeState.flooded);
				assert(s.getTube(0).desiredState == TubeState.dry);
				return;
			}
			case 1 + 11 + 6 + 3 + 1 + 3 + 3 + 6:
			{
				assert(s.getTube(0).lastSimUpdateResult.tubeChanged);
				assert(s.getTube(0).state == TubeState.dry);
				assert(s.getTube(0).desiredState == TubeState.dry);
				return;
			}
			default:
				return;
		}
	};

	Globals.sim.start();
	Globals.sim.join();

	assert(!s.dead, "self-detonation on flank");

	Globals.resetForTests();
}