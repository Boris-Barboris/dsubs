module dsubs_client.game.simulation;

import std.algorithm;
import std.array;
import std.conv: to;
import std.math;
import std.experimental.logger;

import core.thread;

import derelict.sfml2.window;

import dsubs_common.api;

import dsubs_client.core.utils;
import dsubs_client.game;
import dsubs_client.gui;
import dsubs_client.game.cameracontroller;


class SimulatorState
{
	Submarine playerSub;
}


/// setup the state of the game itself
void setupSimulationState(Submarine playerSub)
{
	Game.clearEntities();

	if (!Game.serverConnection.connected)
	{
		error("Connection was lost, falling back to main menu");
		// TRANSITION TO MAIN MENU
		setupMainMenu();
		return;
	}

	Game.simState = new SimulatorState();
	Game.simState.playerSub = playerSub;
	Game.worldManager.components ~= playerSub;
	Game.worldManager.camCtx.camera.zoom = 10.0;

	Game.serverConnection.onConnectionClosed += (string reason)
	{
		error("Connection was closed, reason: ", reason);
		// TRANSITION TO MAIN MENU
		setupMainMenu();
	};

	// set up submarine coordinate update
	bool camSetOnSub = false;
	Game.serverConnection.onSubKinematicRes += (SubKinematicRes res)
	{
		Game.simState.playerSub.updateKinematics(res.snap);
		if (!camSetOnSub)
		{
			Game.worldManager.camCtx.camera.center = res.snap.position.toGfm;
			camSetOnSub = true;
		}
	};

	// set up camera
	Game.worldManager.mouseReceivers ~= new CameraController();
}