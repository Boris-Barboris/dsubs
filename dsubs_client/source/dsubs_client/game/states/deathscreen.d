module dsubs_client.game.states.deathscreen;

import std.utf;

import core.thread;

import derelict.sfml2.window;
import derelict.sfml2.system;

import dsubs_common.api;
import dsubs_common.api.protocols.backend;

import dsubs_client.common;
import dsubs_client.core.utils;
import dsubs_client.game;
import dsubs_client.game.gamestate;
import dsubs_client.game.states.mainmenu;
import dsubs_client.game.cic.server;
import dsubs_client.game.cic.messages;
import dsubs_client.gui;


private
{
	enum int MENU_BUTTON_FONTSIZE = 50;
	enum int YOU_DIED_FONTSIZE = 70;
	enum sfColor YOU_DIED_FONTCOLOR = sfColor(255, 50, 50, 255);
	enum int CAUSE_FONTSIZE = 25;
	enum int BUTTON_FONTSIZE = 40;
}


final class DeathScreenState: GameState
{
	private
	{
		CICDeathRes m_deathRes;
	}

	this(CICDeathRes deathRes)
	{
		m_deathRes = deathRes;
	}

	override void setup()
	{
		Game.window.title = "dsubs";

		Label youDiedLabel = builder(new Label()).content("YOU DIED").
			htextAlign(HTextAlign.CENTER).fontSize(YOU_DIED_FONTSIZE).
			fontColor(YOU_DIED_FONTCOLOR).build();
		Label causeLabel = builder(new Label()).content(m_deathRes.cause).
			htextAlign(HTextAlign.CENTER).fontSize(CAUSE_FONTSIZE).build();
		Button goToMainMenu = builder(new Button()).content("return to main menu").
			htextAlign(HTextAlign.CENTER).fontSize(BUTTON_FONTSIZE).build();

		goToMainMenu.onClick += () { Game.activeState = new MainMenuState(); };

		Div textDiv = builder(vDiv([youDiedLabel, causeLabel, goToMainMenu])).borderWidth(20).
			fixedSize(vec2i(50, 250)).build();
		Div screenLayout = vDiv([
			filler(),
			textDiv,
			filler()
		]);

		Game.guiManager.addPanel(new Panel(screenLayout));
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