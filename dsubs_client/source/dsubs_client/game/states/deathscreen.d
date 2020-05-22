module dsubs_client.game.states.deathscreen;

import std.utf;

import core.thread;

import derelict.sfml2.window;
import derelict.sfml2.system;

import dsubs_common.api;
import dsubs_common.api.messages;

import dsubs_client.common;
import dsubs_client.core.utils;
import dsubs_client.game;
import dsubs_client.game.gamestate;
import dsubs_client.game.states.loginscreen;
import dsubs_client.game.states.loadout;
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
		CICSimFlowEndRes m_deathRes;
	}

	this(CICSimFlowEndRes deathRes)
	{
		m_deathRes = deathRes;
	}

	override void setup()
	{
		Game.window.title = "dsubs";

		string mainLabel;
		final switch (m_deathRes.res.reason)
		{
			case SimFlowEndReason.death:
				mainLabel = "YOU DIED";
				break;
			case SimFlowEndReason.victory:
				mainLabel = "VICTORY";
				break;
			case SimFlowEndReason.defeat:
				mainLabel = "DEFEAT";
				break;
		}
		Label youDiedLabel = builder(new Label()).content(mainLabel).
			htextAlign(HTextAlign.CENTER).fontSize(YOU_DIED_FONTSIZE).
			fontColor(YOU_DIED_FONTCOLOR).build();
		Label causeLabel = builder(new Label()).content(m_deathRes.shortReport).
			htextAlign(HTextAlign.CENTER).fontSize(CAUSE_FONTSIZE).build();
		Button goToMainMenu = builder(new Button()).content("return to main menu").
			htextAlign(HTextAlign.CENTER).fontSize(BUTTON_FONTSIZE).build();

		goToMainMenu.onClick += () { Game.activeState = new LoadoutState(); };

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
		Game.activeState = new LoginScreenState();
	}

	override void handleCICDisconnect()
	{
		Game.activeState = new LoginScreenState();
	}
}