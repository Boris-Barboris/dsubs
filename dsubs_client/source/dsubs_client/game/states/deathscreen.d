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
		bool m_simTerminated;
		CICSimFlowEndRes m_deathRes;
	}

	this(CICSimFlowEndRes deathRes)
	{
		m_deathRes = deathRes;
	}

	/// Used to handle in abrupt
	this()
	{
		m_simTerminated = true;
	}

	override void setup()
	{
		Game.window.title = "dsubs";

		string mainLabel;
		if (m_simTerminated)
			mainLabel = "Simulation was terminated";
		else
		{
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
		}
		Label youDiedLabel = builder(new Label()).content(mainLabel).
			htextAlign(HTextAlign.CENTER).fontSize(YOU_DIED_FONTSIZE).
			fontColor(YOU_DIED_FONTCOLOR).build();
		string shortReport;
		if (m_simTerminated)
			shortReport = "Simulator was abruptly terminated";
		else
			shortReport = m_deathRes.shortReport;
		Label causeLabel = builder(new Label()).content(shortReport).
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

	// these disconnects and aborts do not require immediate state switch, we can
	// continue in loadout state.

	override void handleCICDisconnect() {}

	override void handleSimulatorTerminatingRes() {}
}