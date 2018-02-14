module dsubs_client.game.simulation;

import std.algorithm;
import std.array;
import std.conv: to;
import std.math;
import std.utf;
import std.experimental.logger;

import core.thread;

import derelict.sfml2.window;

import dsubs_common.api;

import dsubs_client.core.utils;
import dsubs_client.game;
import dsubs_client.gui;


private
{
	immutable int BTN_SIZE = 26;
	immutable int BTN_FONT = 20;
	immutable sfColor HINT_COLOR = sfColor(150, 150, 150, 255);
}


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
}