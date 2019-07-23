module dsubs_client.game.states.loadout;

import std.algorithm;
import std.array;
import std.conv: to;
import std.math;
import std.utf;
import std.experimental.logger;

import core.thread;

import derelict.sfml2.window;

import dsubs_common.api;
import dsubs_common.api.protocols.backend;

import dsubs_client.core.utils;
import dsubs_client.game;
import dsubs_client.game.entities;
import dsubs_client.game.gamestate;
import dsubs_client.game.states.mainmenu;
import dsubs_client.game.states.simulation;
import dsubs_client.game.cic.server;
import dsubs_client.gui;
import dsubs_client.input.hotkeymanager;


private
{
	enum int BTN_SIZE = 26;
	enum int BTN_FONT = 20;
	enum int WPN_FONT = 18;
	enum sfColor HINT_COLOR = sfColor(150, 150, 150, 255);
}


final class LoadoutState: GameState
{
	private
	{
		Submarine curSelectedSub;
		TextBox hullDescriptionBox;
		Button startButton;
		string curSelectedPropulsor;
		AmmoRoomTemplate[int] roomTemplates;
		int[string][int] roomLoadouts;
		Label[int] roomHeaders;
		string[] availableHulls;
		Div rightColumnDiv;
		ScrollBar rightColumnScrollbar;
	}

	override void handleBackendDisconnect()
	{
		error("backend connection closed");
		Game.activeState = new MainMenuState();
	}

	override void handleCICDisconnect()
	{
		error("cic connection closed");
		Game.activeState = new MainMenuState();
	}

	private string getRoomCapacityString(int roomId)
	{
		return roomTemplates[roomId].name ~ " " ~
			roomLoadouts[roomId].byValue.sum().to!string ~ "/" ~
			roomTemplates[roomId].capacity.to!string;
	}

	private void trySetWeaponCount(int roomId, TextField field, string weaponName)
	{
		scope(exit) roomHeaders[roomId].content = getRoomCapacityString(roomId);
		if (field.content.length <= 1)	// content is C-string
		{
			field.content = "0";
			field.moveCursorToEnd();
			roomLoadouts[roomId][weaponName] = 0;
		}
		else
		{
			try
			{
				int newCount = max(0, field.content.str.to!int);
				int oldCount = roomLoadouts[roomId][weaponName];
				int roomExcess = (roomLoadouts[roomId].byValue.sum() +
					newCount - oldCount) - roomTemplates[roomId].capacity;
				if (roomExcess > 0)
					newCount -= roomExcess;
				field.content = newCount.to!string;
				roomLoadouts[roomId][weaponName] = newCount;
			}
			catch (Exception ex)
			{
				field.content = roomLoadouts[roomId][weaponName].to!string;
			}
		}
	}

	private Div buildWeaponCountDiv(int roomId, string weaponName, int initialCount)
	{
		Label weaponNameLabel = builder(new Label()).content(weaponName).
			fontSize(WPN_FONT).build;
		weaponNameLabel.onMouseEnter += (o) {
			hullDescriptionBox.content =
					Game.entityManager.weaponTemplates[weaponName].description;
		};
		TextField weaponCountField = builder(new TextField()).
			content(initialCount.to!string).fixedSize(vec2i(45, BTN_FONT)).
			fontSize(BTN_FONT).build;
		weaponCountField.onKeyReleased += (k) {
			trySetWeaponCount(roomId, weaponCountField, weaponName);
		};
		return builder(hDiv([weaponNameLabel, weaponCountField])).
			fixedSize(vec2i(200, BTN_FONT)).build();
	}

	void selectHull(string hullname)
	{
		if (curSelectedSub is null || curSelectedSub.tmpl.name != hullname)
		{
			Game.worldManager.components.length = 0;
			const SubmarineTemplate* subTmpl =
				Game.entityManager.submarineTemplates[hullname];
			const string[] propulsorNames = subTmpl.propulsors;
			assert(propulsorNames.length > 0);
			curSelectedPropulsor = propulsorNames[0];
			GuiElement[] divElements;

			// build scrollist of propulsors
			divElements ~= builder(new Label()).content("Propulsors:").
				fontSize(BTN_FONT).fontColor(HINT_COLOR).
				fixedSize(vec2i(1, 30)).build;
			foreach (propName; propulsorNames)
			{
				Button propSelector = builder(new Button()).content(propName).
					fontSize(BTN_FONT).fixedSize(vec2i(200, BTN_SIZE)).
					htextAlign(HTextAlign.LEFT).build();
				divElements ~= propSelector;
				propSelector.onClick += ()
					{
						curSelectedPropulsor = propName;
						if (curSelectedSub)
							curSelectedSub.setPropulsor(Game.entityManager, propName);
					};
				propSelector.onMouseEnter += (o)
					{
						hullDescriptionBox.content =
							Game.entityManager.propTemplates[propName].description;
					};
			}
			divElements ~= filler(10);

			// build ammo room gui
			roomLoadouts.clear();
			roomTemplates.clear();
			roomHeaders.clear();

			foreach (const AmmoRoomTemplate ammoRoom; subTmpl.ammoRooms)
			{
				roomTemplates[ammoRoom.id] = cast() ammoRoom;
				Label roomHeader = builder(new Label()).content(ammoRoom.name).
					fontSize(BTN_FONT).fontColor(HINT_COLOR).fixedSize(vec2i(1, 30)).build;
				roomHeaders[ammoRoom.id] = roomHeader;
				divElements ~= roomHeader;
				assert(ammoRoom.allowedWeaponSet.weaponNames.length > 0);
				int[string] defaultLoadout;
				foreach (i, weaponName; ammoRoom.allowedWeaponSet.weaponNames)
				{
					int count = 0;
					if (i == 0)
						count = ammoRoom.capacity;
					defaultLoadout[weaponName] = count;
					divElements ~= buildWeaponCountDiv(ammoRoom.id, weaponName, count);
				}
				roomLoadouts[ammoRoom.id] = defaultLoadout;
				roomHeader.content = getRoomCapacityString(ammoRoom.id);
			}

			// build scrollable div that combines propulsors, racks and tubes
			int totalDivHeight = divElements.map!(e => e.size.y).sum();
			Div combinedDiv = builder(vDiv(divElements)).fixedSize(
				vec2i(200, totalDivHeight)).build;
			rightColumnScrollbar = new ScrollBar(combinedDiv);
			if (rightColumnDiv)
				rightColumnDiv.setChild(rightColumnScrollbar, 0);

			curSelectedSub = new Submarine(Game.entityManager, hullname,
				curSelectedPropulsor);
			curSelectedSub.targetThrottle = 0.1f;
			curSelectedSub.transform.rotation = -PI_2;
			Game.worldManager.components ~= curSelectedSub;
		}
	}

	override void setup()
	{
		availableHulls = Game.entityDb.controllableSubs.map!(a => a.name).array;

		/* Layout:
		Hull1 |				| hull_props
		Hull2 |				| racks
		Hull3 |_____________| tubes
			  |	Description	|Play
		*/

		hullDescriptionBox = new TextBox();
		hullDescriptionBox.fontSize = 16;

		// scrollist of available hulls
		GuiElement[] hullButtons;
		foreach (i, hullname; availableHulls)
		{
			Button hullSelector = builder(new Button()).content(hullname).
				fontSize(BTN_FONT).fixedSize(vec2i(200, BTN_SIZE)).
				htextAlign(HTextAlign.LEFT).build();
			hullButtons ~= hullSelector;
			hullSelector.onClick += { selectHull(hullname); };
			hullSelector.onMouseEnter += (o)
				{
					hullDescriptionBox.content =
						Game.entityManager.submarineTemplates[hullname].description;
				};
			if (i == 0)
			{
				assert(curSelectedSub is null);
				// select first submarine in the list
				hullSelector.simulateClick();
				hullSelector.onMouseEnter(null);
				hullSelector.onMouseLeave(null);
				assert(curSelectedSub !is null);
			}
		}

		Div hullDiv = builder(vDiv(hullButtons)).layoutType(LayoutType.CONTENT).
			size(vec2i(200, BTN_SIZE * availableHulls.length.to!int +
							availableHulls.length.to!int)).build;
		ScrollBar hullsScrollbar = new ScrollBar(hullDiv);

		startButton = builder(new Button(ButtonType.ASYNC)).fontSize(45).
			htextAlign(HTextAlign.CENTER).content("Start").fixedSize(vec2i(1, 70)).
			build();
		startButton.onClick += ()
			{
				if (curSelectedSub is null)
				{
					hullDescriptionBox.content = "You must select a submarine!";
					startButton.signalClickEnd();
					return;
				}
				// we can send spawn request to the server
				immutable SpawnReq req = immutable SpawnReq(
					curSelectedSub.tmpl.name, curSelectedPropulsor,
					roomLoadouts.byKey.map!(roomId =>
						AmmoRoomFullState(
							roomId,
							roomLoadouts[roomId].byKey.map!(weaponName =>
								WeaponCount(
									weaponName,
									roomLoadouts[roomId][weaponName]
								)).array
						)).array
					);
				trace("Requesting spawn: ", req);
				Game.bconm.con.sendMessage(req);
			};

		Game.hotkeyManager.setHotkey(Hotkey(sfKeyReturn),
			() { startButton.simulateClick(); });

		rightColumnDiv = builder(vDiv([
				rightColumnScrollbar,
				startButton
				])
			).fixedSize(vec2i(250, 1)).build();

		auto prepareGui = hDiv([
			builder(vDiv([
						builder(new Label()).content("Hulls:").
							fontSize(BTN_FONT).fontColor(HINT_COLOR).
							fixedSize(vec2i(1, 30)).build,
						hullsScrollbar
					])
				).fixedSize(vec2i(150, 1)).build(),
			filler(20),
			vDiv([
				builder(new Label()).fontSize(BTN_FONT).
					fixedSize(vec2i(1, BTN_SIZE)).fontColor(HINT_COLOR).
					content("Description").build,
				new ScrollBar(hullDescriptionBox),
				filler(0.75f)
			]),
			filler(20),
			rightColumnDiv
		]);

		Game.guiManager.addPanel(new Panel(prepareGui));
		Game.worldManager.camCtx.camera.zoom = 10.0;
		Game.worldManager.camCtx.camera.center = vec2d(0.0, 0.0);

		Game.render.onPreRender += (delta) {
			int wndX = Game.window.size.x;
			Game.worldManager.camCtx.camera.zoom = wndX / 120.0f;
		};
	}

	void handleSpawnRes(SpawnRes res)
	{
		if (res.spawnAllowed)
		{
			// we need to create new CIC server
			if (Game.cic)
				Game.cic.stop();
			info("building new CIC server");
			Game.cic = new CICServer("", Game.bconm.con);
			info("starting CIC");
			Game.cic.start();
			info("connecting to local CIC");
			ushort port = Game.cic.listener.port;
			Game.ciccon = CICClientConnection.connect("127.0.0.1:" ~ port.to!string, "");
			// CIC client will perform simulator bootstrap from here
			return;
		}
		else if (res.secsLeft >= 0)
		{
			hullDescriptionBox.content = "Respawn available in " ~
				res.secsLeft.to!string ~ " seconds";
			Game.delay(() { startButton.signalClickEnd(); },
				seconds(res.secsLeft + 1));
		}
		else
			startButton.signalClickEnd();
	}

}