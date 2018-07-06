module dsubs_client.game.states.mainmenu;

import std.utf;

import core.thread;

import derelict.sfml2.window;

import dsubs_common.api;
import dsubs_common.api.protocols.backend;

import dsubs_client.common;
import dsubs_client.core.utils;
import dsubs_client.game;
import dsubs_client.game.gamestate;
import dsubs_client.game.states.loadout;
import dsubs_client.game.entities;
import dsubs_client.gui;


private
{
	enum int MENU_BUTTON_FONTSIZE = 50;
	enum int LOGIN_FONT_SIZE = 22;
	enum int INFO_FONT_SIZE = 18;
	enum float LOGIN_FRACT = 0.3f;
}


final class MainMenuState: GameState
{
	this()
	{
		super(GameStateKind.MAINMENU);
	}

	private
	{
		bool canLogin;
		bool alreadySpawned;
		ReconnectStateRes recState;
		Label infoLabel;
		Button connectButton;
	}

	override void setup()
	{
		int btnSize = (MENU_BUTTON_FONTSIZE * 1.3).lrint.to!int;
		connectButton = builder(new Button(ButtonType.ASYNC)).content("Authorize").
			fontSize(MENU_BUTTON_FONTSIZE).fixedSize(vec2i(400, btnSize)).build();

		infoLabel = builder(new Label()).content("Connecting to server").
			fontSize(INFO_FONT_SIZE).fixedSize(vec2i(400, INFO_FONT_SIZE + 10)).
			fontColor(sfColor(255, 255, 0, 255)).htextAlign(HTextAlign.CENTER).build();

		int loginSize = (LOGIN_FONT_SIZE * 1.3).lrint.to!int;
		Label loginLabel = builder(new Label()).content("Login:").
			htextAlign(HTextAlign.LEFT).fontSize(LOGIN_FONT_SIZE).fraction(LOGIN_FRACT).build();
		TextField loginField = builder(new TextField()).fontSize(LOGIN_FONT_SIZE).build();

		Label pwLabel = builder(new Label()).content("Password:").
			htextAlign(HTextAlign.LEFT).fontSize(LOGIN_FONT_SIZE).fraction(LOGIN_FRACT).build();
		PasswordField pwField = builder(new PasswordField()).fontSize(LOGIN_FONT_SIZE).build();

		Div credDiv = builder(vDiv([
				hDiv([loginLabel, loginField, filler(LOGIN_FRACT)]),
				hDiv([pwLabel, pwField, filler(LOGIN_FRACT)])
			])).fixedSize(vec2i(0, loginSize * 2 + 20)).borderWidth(20).build();

		loginField.onKeyPressed += (evt)
		{
			if (evt.code == sfKeyTab)
				pwField.requestKbFocus();
			if (evt.code == sfKeyReturn)
				connectButton.simulateClick();
		};

		pwField.onKeyPressed += (evt)
		{
			if (evt.code == sfKeyReturn)
				connectButton.simulateClick();
		};

		// Game.serverConnection.onEntityDbRecieved += (EntityDbRes res)
		// {
		// 	trace("Entity database recieved");
		// 	infoLabel.content = "got database with " ~
		// 		res.controllableSubs.length.to!string ~ " submarines";
		// 	Game.entityDb = res;
		// 	trace("Building entity manager");
		// 	Game.entityManager = new EntityManager(Game.entityDb);

		// 	if (alreadySpawned)
		// 	{
		// 		Submarine playerSub = new Submarine(
		// 			Game.entityManager, recState.submarineName, recState.propulsorName);
		// 		playerSub.targetCourse = recState.targetCourse;
		// 		playerSub.targetThrottle = recState.targetThrottle;
		// 		setupSimulationState(playerSub, true);
		// 		return;
		// 	}

		// 	// TRANSITION TO LOADOUT SCREEN
		// 	setupLoadoutScreen();
		// };

		connectButton.onClick += (b)
		{
			if (!canLogin)
			{
				connectButton.signalClickEnd();
				return;
			}
			Game.bconm.con.sendMessage(
				immutable LoginReq(loginField.content.str, pwField.content.str));
			infoLabel.content = "Authorizing...";
		};

		Button exitButton = builder(new Button()).content("Exit").
			fontSize(MENU_BUTTON_FONTSIZE).
			fixedSize(vec2i(400, btnSize)).build();
		exitButton.onClick += (b) { Game.window.stopEventProcessing(); };

		Div mainMenuDiv = builder(vDiv([
			filler(),
			credDiv,
			filler(30),
			connectButton,
			infoLabel,
			filler(50),
			exitButton,
			filler()
		])).fixedSize(vec2i(600, 10)).build();

		Div mainMenuLayout = hDiv([
			filler(),
			mainMenuDiv,
			filler()
		]);

		Game.guiManager.addPanel(new Panel(mainMenuLayout));
		loginField.requestKbFocus();
	}

	void handleServerStatus(ServerStatusRes res)
	{
		if (res.apiVersion != ServerStatusRes.init.apiVersion)
		{
			string errorStr = "Incompatible API versions, client " ~
				ServerStatusRes.init.apiVersion.to!string ~
				", server " ~ res.apiVersion.to!string;
			error(errorStr);
			infoLabel.content = errorStr;
			return;
		}
		canLogin = true;
		infoLabel.content = res.playersOnline.to!string ~ " players online";
	}

	void handleReconnectState(ReconnectStateRes res)
	{
		alreadySpawned = true;
		recState = res;
	}

	void handleLogin(LoginRes res)
	{
		if (res.success)
		{
			info("login successfull");
			infoLabel.content = res.welcomeMsg;
			canLogin = false;
			infoLabel.content = "Requesting entity database";
			Game.bconm.con.sendMessage(immutable EntityDbReq());
			// check if we are already swimming out there on the server
			if (res.alreadySpawned)
			{
				info("Player is already spawned");
				alreadySpawned = true;
			}
		}
		else
		{
			infoLabel.content = "Unable to log in: " ~ res.welcomeMsg;
		}
		connectButton.signalClickEnd();
	}

	void handleEntityDb(EntityDbRes res)
	{
		Game.entityDb = res;
		Game.entityManager = new EntityManager(Game.entityDb);

		// if (alreadySpawned)
		// {
		// 	Submarine playerSub = new Submarine(
		// 		Game.entityManager, recState.submarineName, recState.propulsorName);
		// 	playerSub.targetCourse = recState.targetCourse;
		// 	playerSub.targetThrottle = recState.targetThrottle;
		// 	setupSimulationState(playerSub, true);
		// 	return;
		// }

		Game.activeState = new LoadoutState();
	}

	override void handleBackendDisconnect()
	{
		canLogin = alreadySpawned = false;
		infoLabel.content = "Backend server connection closed";
		connectButton.signalClickEnd();
	}

	override void handleCICDisconnect() {}
}