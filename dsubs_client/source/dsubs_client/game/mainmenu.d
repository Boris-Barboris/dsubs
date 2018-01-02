module dsubs_client.game.mainmenu;

import std.conv: to;
import std.math;
import std.utf;
import std.experimental.logger;

import derelict.sfml2.window;

import dsubs_common.api;

import dsubs_client.core.utils;
import dsubs_client.game;
import dsubs_client.gui;


__gshared bool canLogin = false;

void setupMainMenu()
{
	canLogin = false;
	int MENU_BUTTON_FONTSIZE = 50;
	int LOGIN_FONT_SIZE = 22;
	int INFO_FONT_SIZE = 18;
	float LOGIN_FRACT = 0.3f;

	Game.clearEntities();

	int btnSize = (MENU_BUTTON_FONTSIZE * 1.3).lrint.to!int;
	Button connectButton = builder(new Button(ButtonType.ASYNC)).content("Connect").
		fontSize(MENU_BUTTON_FONTSIZE).size(vec2i(400, btnSize)).
		layoutType(LayoutType.FIXED).build();
	
	Label infoLabel = builder(new Label()).content("Connecting to server").
		fontSize(INFO_FONT_SIZE).size(vec2i(400, INFO_FONT_SIZE + 10)).
		fontColor(sfColor(255, 255, 0, 255)).layoutType(LayoutType.FIXED).build();

	int loginSize = (LOGIN_FONT_SIZE * 1.3).lrint.to!int;
	Label loginLabel = builder(new Label()).content("Your nickname:").
		htextAlign(HTextAlign.LEFT).fontSize(LOGIN_FONT_SIZE).fraction(LOGIN_FRACT).
		layoutType(LayoutType.FRACT).build();
	TextField loginField = builder(new TextField()).fontSize(LOGIN_FONT_SIZE).build();

	Label pwLabel = builder(new Label()).content("Password:").
		htextAlign(HTextAlign.LEFT).fontSize(LOGIN_FONT_SIZE).fraction(LOGIN_FRACT).
		layoutType(LayoutType.FRACT).build();
	PasswordField pwField = builder(new PasswordField()).fontSize(LOGIN_FONT_SIZE).build();

	loginField.onKeyPressed += (evt) {
		if (evt.code == sfKeyTab)
		{
			loginField.returnKbFocus();
			pwField.requestKbFocus();
		}
	};

	pwField.onKeyPressed += (evt) {
		if (evt.code == sfKeyReturn)
			connectButton.simulateClick();
	};

	Div credDiv = builder(vDiv([
		hDiv([loginLabel, loginField, filler(LOGIN_FRACT)]),
		hDiv([pwLabel, pwField, filler(LOGIN_FRACT)])
	])).layoutType(LayoutType.FIXED).size(vec2i(0, loginSize * 2 + 20)).
	borderWidth(20).build();

	void handleConnectOk(ServerStatusRes res)
	{
		if (res.apiVersion != API_VERSION)
		{
			error("Incompatible API versions, local ", API_VERSION, 
				", remote ", res.apiVersion);
			infoLabel.content = "Incompatible API, update client";
		}
		canLogin = true;
		infoLabel.content = res.playersOnline.to!string ~ " players online";
	}

	if (Game.serverConnection.connected)
		handleConnectOk(Game.serverConnection.lastServerStatus);	
	Game.serverConnection.onConnectionSuccess += &handleConnectOk;

	Game.serverConnection.onLoginRes += (LoginRes res)
	{
		if (res.success)
		{
			connectButton.content = "Connected";
			infoLabel.content = res.welcomeMsg;
			canLogin = false;
		}
		else
		{
			connectButton.content = "Connect";
			infoLabel.content = "Unable to authorize: " ~ res.welcomeMsg;
		}
		connectButton.signalClickEnd();
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
		connectButton.content = "Connecting...";
	};
	
	Button exitButton = builder(new Button()).content("Exit").fontSize(MENU_BUTTON_FONTSIZE).
		size(vec2i(400, btnSize)).layoutType(LayoutType.FIXED).build();
	exitButton.onClick += (b) { Game.window.stopEventProcessing(); };
	
	Div mainMenuDiv = builder(vDiv([
		new GuiElement(),
		credDiv,
		filler(30),
		connectButton,
		infoLabel,
		filler(50),
		exitButton,
		new GuiElement()
	])).layoutType(LayoutType.FIXED).size(vec2i(600, 10)).build();
	
	Div mainMenuLayout = hDiv([
		new GuiElement(),
		mainMenuDiv,
		new GuiElement()
	]);
	
	Game.guiManager.addPanel(new Panel(mainMenuLayout));
	loginField.requestKbFocus();
}