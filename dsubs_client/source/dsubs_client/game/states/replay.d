module dsubs_client.game.states.replay;

import std.datetime;

import derelict.sfml2.window;
import derelict.sfml2.system;

import dsubs_common.api.messages;
import dsubs_common.api.entities;

import dsubs_client.common;
import dsubs_client.core.utils;
import dsubs_client.game;
import dsubs_client.game.gamestate;
import dsubs_client.game.states.mainmenu;
import dsubs_client.gui;


final class ReplayState: GameState
{
	private
	{
		Date day;
		ReplaySlice[] slices;
	}

	this(Date day, ReplaySlice[] slices)
	{
		this.day = day;
		this.slices = slices;
	}

	override void setup()
	{
		trace("got ", slices.length, " slices");
	}

	override void handleBackendDisconnect()
	{
		Game.activeState = new MainMenuState();
	}

	override void handleCICDisconnect()
	{
		Game.activeState = new MainMenuState();
	}
}