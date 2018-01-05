module dsubs_client.game.prepare;

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


void setupPrepareScreen()
{
	enum int BTN_SIZE = 26;
	enum int BTN_FONT = 20;

	Game.clearEntities();

	string[] hulls = Game.entityDb.controllableSubs.map!(a => a.name).array;
	string[] propulsors = Game.entityDb.propulsors.map!(a => a.name).array;

	/* Layout:
	Hull1 |				| prop1
	Hull2 |				| prop2
	Hull3 |_____________|______
		  |	Description	|Play
	*/

	string curSelectedHull;
	string curSelectedPropulsor = propulsors[0];

	TextBox descriptionBox = new TextBox();
	descriptionBox.fontSize = 16;

	// scrollist of hulls
	GuiElement[] hullButtons;
	foreach (hullname; hulls)
	{
		Button hullSelector = builder(new Button()).content(hullname).
			fontSize(BTN_FONT).fixedSize(vec2i(200, BTN_SIZE)).
			htextAlign(HTextAlign.LEFT).build();
		hullButtons ~= hullSelector;
		hullSelector.onClick += (btn)
			{
				if (curSelectedHull != hullname)
				{
					Game.worldManager.components.clear();
					curSelectedHull = hullname;
					Submarine stub = new Submarine(0, Game.entityManager, hullname,
						curSelectedPropulsor);
					stub.transform.rotation = -PI_2;
					Game.worldManager.components ~= stub;
					descriptionBox.content = stub.templ.description;
				}
			};
	}

	Div hullDiv = builder(vDiv(hullButtons)).
		fixedSize(vec2i(200, BTN_SIZE * hulls.length + hulls.length)).borderWidth(1).
		borderColor(sfColor(255, 255, 255, 30)).build;
	ScrollBar hullsScrollbar = new ScrollBar(hullDiv);

	auto prepareGui = hDiv([
		builder(vDiv([
					builder(new Label()).content("Available submarines:").
						fontSize(BTN_FONT).fontColor(sfColor(150, 150, 150, 255)).
						fixedSize(vec2i(1, 30)).build,
					hullsScrollbar
				])
			).fraction(0.25f).build(),
		vDiv([filler(0.9f), new ScrollBar(descriptionBox)])
	]);

	Game.guiManager.addPanel(new Panel(prepareGui));
	Game.worldManager.camCtx.camera.zoom = 3.0;
}