module dsubs_client.game.loadout;

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
import dsubs_client.game.simulation;
import dsubs_client.gui;
import dsubs_client.input.hotkeymanager;


private
{
	immutable int BTN_SIZE = 26;
	immutable int BTN_FONT = 20;
	immutable sfColor HINT_COLOR = sfColor(150, 150, 150, 255);
}


/// setup game state to present loadout screen
void setupLoadoutScreen()
{
	Game.clearEntities();

	if (!Game.serverConnection.connected)
	{
		error("Connection was lost, falling back to main menu");
		// TRANSITION TO MAIN MENU
		setupMainMenu();
		return;
	}

	Game.serverConnection.onConnectionClosed += (string reason)
	{
		error("Connection was closed, reason: ", reason);
		// TRANSITION TO MAIN MENU
		setupMainMenu();
	};

	string[] hulls = Game.entityDb.controllableSubs.map!(a => a.name).array;
	string[] propulsors = Game.entityDb.propulsors.map!(a => a.name).array;

	/* Layout:
	Hull1 |				| prop1
	Hull2 |				| prop2
	Hull3 |_____________|______
		  |	Description	|Play
	*/

	string curSelectedPropulsor = propulsors[0];
	Submarine curSelectedSub;

	TextBox hullDescriptionBox = new TextBox();
	hullDescriptionBox.fontSize = 16;

	// scrollist of hulls
	GuiElement[] hullButtons;
	foreach (i, hullname; hulls)
	{
		Button hullSelector = builder(new Button()).content(hullname).
			fontSize(BTN_FONT).fixedSize(vec2i(200, BTN_SIZE)).
			htextAlign(HTextAlign.LEFT).build();
		hullButtons ~= hullSelector;
		hullSelector.onClick += (btn)
			{
				if (curSelectedSub is null || curSelectedSub.tmpl.name != hullname)
				{
					Game.worldManager.components.length = 0;
					curSelectedSub = new Submarine(Game.entityManager, hullname,
						curSelectedPropulsor);
					curSelectedSub.transform.rotation = -PI_2;
					Game.worldManager.components ~= curSelectedSub;
				}
			};
		hullSelector.onMouseEnter += ()
			{
				hullDescriptionBox.content =
					Game.entityManager.submarineTemplates[hullname].description;
			};
		if (i == 0)
		{
			assert(curSelectedSub is null);
			hullSelector.simulateClick();	// select first submarine in the list
			assert(curSelectedSub !is null);
		}
	}

	Div hullDiv = builder(vDiv(hullButtons)).layoutType(LayoutType.CONTENT).
		size(vec2i(200, BTN_SIZE * hulls.length + hulls.length)).build;
	ScrollBar hullsScrollbar = new ScrollBar(hullDiv);

	TextBox moduleDescriptionBox = new TextBox();
	moduleDescriptionBox.fontSize = 16;

	// scrollist of propulsors
	GuiElement[] propButtons;
	foreach (propName; propulsors)
	{
		Button propSelector = builder(new Button()).content(propName).
			fontSize(BTN_FONT).fixedSize(vec2i(200, BTN_SIZE)).
			htextAlign(HTextAlign.LEFT).build();
		propButtons ~= propSelector;
		propSelector.onClick += (btn)
			{
				curSelectedPropulsor = propName;
				if (curSelectedSub)
					curSelectedSub.setPropulsor(Game.entityManager, propName);
			};
		propSelector.onMouseEnter += ()
			{
				moduleDescriptionBox.content =
					Game.entityManager.propTemplates[propName].description;
			};
	}

	Div propsDiv = builder(vDiv(propButtons)).layoutType(LayoutType.CONTENT).
		size(vec2i(200, BTN_SIZE * hulls.length + hulls.length)).build;
	ScrollBar propsScrollbar = new ScrollBar(propsDiv);


	Button startButton = builder(new Button(ButtonType.ASYNC)).fontSize(45).
		htextAlign(HTextAlign.CENTER).content("Start").fixedSize(vec2i(1, 70)).
		build();
	startButton.onClick += (btn)
		{
			if (curSelectedSub is null)
			{
				hullDescriptionBox.content = "You must select a submarine!";
				startButton.signalClickEnd();
				return;
			}
			// we can send spawn request to the server
			immutable(SpawnReq)* req = new SpawnReq(
				curSelectedSub.tmpl.name, curSelectedPropulsor);
			trace("Requesting spawn: ", *req);
			Game.serverConnection.sendMessage(req);
		};

	Game.hotkeyManager.setHotkey(Hotkey(sfKeyReturn),
		() { startButton.simulateClick(); });

	Game.serverConnection.onSpawnRes += (SpawnRes res)
		{
			if (res.spawnAllowed)
			{
				startButton.signalClickEnd();
				/// TRANSITION TO SIMULATION GAME STATE
				setupSimulationState(curSelectedSub);
				return;
			}
			if (res.secsLeft >= 0)
			{
				hullDescriptionBox.content = "Respawn available in " ~
					res.secsLeft.to!string ~ " seconds";
				Game.delay(() { startButton.signalClickEnd(); },
					seconds(res.secsLeft + 1));
			}
			else
				startButton.signalClickEnd();
		};

	auto prepareGui = hDiv([
		builder(vDiv([
					builder(new Label()).content("Available submarines:").
						fontSize(BTN_FONT).fontColor(HINT_COLOR).
						fixedSize(vec2i(1, 30)).build,
					hullsScrollbar
				])
			).fraction(0.25f).build(),
		vDiv([
			new ScrollBar(moduleDescriptionBox),
			filler(0.5f),
			builder(new Label()).fontSize(BTN_FONT).
				fixedSize(vec2i(1, BTN_SIZE)).fontColor(HINT_COLOR).
				content("Hull description").build,
			new ScrollBar(hullDescriptionBox)
		]),
		builder(vDiv([
					builder(new Label()).content("Available propulsors:").
						fontSize(BTN_FONT).fontColor(HINT_COLOR).
						fixedSize(vec2i(1, 30)).build,
					propsScrollbar,
					startButton
				])
			).fraction(0.25f).build(),
	]);
	prepareGui.borderColor = sfColor(50, 50, 50, 100);
	prepareGui.borderWidth = 1;

	Game.guiManager.addPanel(new Panel(prepareGui));
	Game.worldManager.camCtx.camera.zoom = 10.0;
	Game.worldManager.camCtx.camera.center = vec2d(0.0, 0.0);
}