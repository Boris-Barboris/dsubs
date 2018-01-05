module dsubs_client.game.mainmenu;

import std.conv: to;
import std.math;
import std.utf;
import std.experimental.logger;

import core.thread;

import derelict.sfml2.window;

import dsubs_common.api;

import dsubs_client.core.utils;
import dsubs_client.game;
import dsubs_client.game.prepare;
import dsubs_client.gui;


private __gshared bool canLogin = false;


void setupMainMenu()
{
	canLogin = false;

	enum int MENU_BUTTON_FONTSIZE = 50;
	enum int LOGIN_FONT_SIZE = 22;
	enum int INFO_FONT_SIZE = 18;
	enum float LOGIN_FRACT = 0.3f;

	Game.clearEntities();

	int btnSize = (MENU_BUTTON_FONTSIZE * 1.3).lrint.to!int;
	Button connectButton = builder(new Button(ButtonType.ASYNC)).content("Authorize").
		fontSize(MENU_BUTTON_FONTSIZE).fixedSize(vec2i(400, btnSize)).build();
	
	Label infoLabel = builder(new Label()).content("Connecting to server").
		fontSize(INFO_FONT_SIZE).fixedSize(vec2i(400, INFO_FONT_SIZE + 10)).
		fontColor(sfColor(255, 255, 0, 255)).htextAlign(HTextAlign.CENTER).build();

	int loginSize = (LOGIN_FONT_SIZE * 1.3).lrint.to!int;
	Label loginLabel = builder(new Label()).content("Your nickname:").
		htextAlign(HTextAlign.LEFT).fontSize(LOGIN_FONT_SIZE).fraction(LOGIN_FRACT).build();
	TextField loginField = builder(new TextField()).fontSize(LOGIN_FONT_SIZE).build();

	Label pwLabel = builder(new Label()).content("Password:").
		htextAlign(HTextAlign.LEFT).fontSize(LOGIN_FONT_SIZE).fraction(LOGIN_FRACT).build();
	PasswordField pwField = builder(new PasswordField()).fontSize(LOGIN_FONT_SIZE).build();

	Div credDiv = builder(vDiv([
			hDiv([loginLabel, loginField, filler(LOGIN_FRACT)]),
			hDiv([pwLabel, pwField, filler(LOGIN_FRACT)])
		])).fixedSize(vec2i(0, loginSize * 2 + 20)).borderWidth(20).build();

	loginField.onKeyPressed += (evt) {
		if (evt.code == sfKeyTab)
			pwField.requestKbFocus();
		if (evt.code == sfKeyReturn)
			connectButton.simulateClick();
	};

	pwField.onKeyPressed += (evt) {
		if (evt.code == sfKeyReturn)
			connectButton.simulateClick();
	};

	void handleConnectOk(ServerStatusRes res)
	{
		if (res.apiVersion != API_VERSION)
		{
			string errorStr = "Incompatible API versions, client " ~
				API_VERSION.to!string ~ ", server " ~ res.apiVersion.to!string;
			error(errorStr);
			infoLabel.content = errorStr;
			return;
		}
		canLogin = true;
		infoLabel.content = res.playersOnline.to!string ~ " players online";
	}

	if (Game.serverConnection.connected)
		handleConnectOk(Game.serverConnection.lastServerStatus);
	Game.serverConnection.onConnectionSuccess += &handleConnectOk;

	Game.serverConnection.onConnectionClosed += (string reason)
	{
		canLogin = false;
		infoLabel.content = "Connection closed: " ~ reason;
		connectButton.signalClickEnd();
	};

	Game.serverConnection.onLoginRes += (LoginRes res)
	{
		if (res.success)
		{
			infoLabel.content = res.welcomeMsg;
			canLogin = false;
			Game.delayer.delay( () {
					infoLabel.content = "Downloading entity database";
					Game.serverConnection.sendMessage(
						new immutable EntityDbReq());
				}, msecs(200), Game.mainMutex);
		}
		else
		{
			infoLabel.content = "Unable to log in: " ~ res.welcomeMsg;
		}
		connectButton.signalClickEnd();
	};

	Game.serverConnection.onEntityDbRecieved += (EntityDbRes res)
	{
		trace("Entity database recieved");
		infoLabel.content = "got database with " ~ 
			res.controllableSubs.length.to!string ~ " submarines";
		Game.entityDb = res;
		trace("Building entity manager");
		Game.entityManager = new EntityManager(Game.entityDb);

		// TRANSITION TO PREPARE SCREEN
		setupPrepareScreen();
	};

	connectButton.onClick += (b)
	{
		if (!canLogin)
		{
			connectButton.signalClickEnd();
			return;
		}
		Game.serverConnection.sendMessage(
			new immutable LoginReq(loginField.content.str, pwField.content.str));
		infoLabel.content = "Logging in...";
	};
	
	Button exitButton = builder(new Button()).content("Exit").fontSize(MENU_BUTTON_FONTSIZE).
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