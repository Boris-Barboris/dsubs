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
import dsubs_common.api.messages;

import dsubs_client.core.utils;
import dsubs_client.common;
import dsubs_client.game;
import dsubs_client.game.entities;
import dsubs_client.game.gamestate;
import dsubs_client.game.states.loginscreen;
import dsubs_client.game.states.simulation;
import dsubs_client.game.cic.server;
import dsubs_client.gui;
import dsubs_client.input.router: IInputReceiver;
import dsubs_client.input.hotkeymanager;


private
{
	enum int BTN_SIZE = 26;
	enum int BTN_FONT = 20;
	enum int WPN_FONT = 18;
	enum int TUBE_FONT = 18;
	enum int TUBE_CONTENT_FONT = 14;
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
		string[int] tubeLoadouts;
		Label[int] roomHeaders;
		ContextMenu tubeContextMenu;
		string[] availableHulls;
		Div rightColumnDiv;
		ScrollBar rightColumnScrollbar;
	}

	override void handleBackendDisconnect()
	{
		error("backend connection closed");
		Game.activeState = new LoginScreenState();
	}

	override void handleCICDisconnect()
	{
		error("cic connection closed");
		Game.activeState = new LoginScreenState();
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

	private ContextMenu buildTubeLoadMenu(int tubeId, Button tubeContentBtn,
		const string[] allowedWeapons, vec2i mousePos)
	{
		Button chooseEmpty = builder(new Button()).
			content("empty").fontSize(TUBE_CONTENT_FONT).build;
		chooseEmpty.onClick += {
			tubeLoadouts[tubeId] = null;
			tubeContentBtn.content = "empty";
		};
		Button[] contextButtons = [chooseEmpty];
		foreach (string allowedWeapon; allowedWeapons)
		{
			Button btn = builder(new Button()).
				content(allowedWeapon).fontSize(TUBE_CONTENT_FONT).build;
			btn.onClick += ((string aw) => {
				tubeLoadouts[tubeId] = aw;
				tubeContentBtn.content = aw;
			}) (allowedWeapon);
			contextButtons ~= btn;
		}
		return contextMenu(Game.guiManager, contextButtons, Game.window.size,
			mousePos, TUBE_CONTENT_FONT + 4);
	}

	private Div buildTubeLoadDiv(int tubeId, string initialWeapon,
		const string[] allowedWeapons)
	{
		Label tubeNameLabel = builder(new Label()).
			content("tube " ~ (tubeId + 1).to!string).fontSize(TUBE_FONT).build;
		Button tubeContentButton = builder(new Button()).
			content(initialWeapon).fontSize(TUBE_FONT).
			backgroundColor(COLORS.simButtonBgnd).fixedSize(vec2i(150, BTN_FONT)).build;
		tubeContentButton.onClick += () {
			tubeContextMenu = buildTubeLoadMenu(tubeId, tubeContentButton,
				allowedWeapons, Game.window.mousePos);
		};
		return builder(hDiv([tubeNameLabel, tubeContentButton])).
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
				fontSize(BTN_FONT).fontColor(COLORS.loadoutHint).
				fixedSize(vec2i(1, 30)).build;
			foreach (propName; propulsorNames)
			{
				Button propSelector = builder(new Button()).content(propName).
					fontSize(BTN_FONT).fixedSize(vec2i(200, BTN_SIZE)).
					htextAlign(HTextAlign.LEFT).build();
				divElements ~= propSelector;
				propSelector.onClick += ((string pn) => ()
					{
						curSelectedPropulsor = pn;
						if (curSelectedSub)
							curSelectedSub.setPropulsor(Game.entityManager, pn);
					})(propName);
				propSelector.onMouseEnter += ((string pn) => (IInputReceiver o)
					{
						hullDescriptionBox.content =
							Game.entityManager.propTemplates[pn].description;
					})(propName);
			}
			divElements ~= filler(15);

			// build gui for ammo rooms
			roomLoadouts.clear();
			roomTemplates.clear();
			roomHeaders.clear();
			tubeLoadouts.clear();
			if (tubeContextMenu)
			{
				tubeContextMenu.rootDiv.returnMouseFocus();
				tubeContextMenu = null;
			}

			foreach (const AmmoRoomTemplate ammoRoom; subTmpl.ammoRooms)
			{
				roomTemplates[ammoRoom.id] = cast() ammoRoom;
				Label roomHeader = builder(new Label()).content(ammoRoom.name).
					fontSize(BTN_FONT).fontColor(COLORS.loadoutHint).fixedSize(vec2i(1, 30)).build;
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
				divElements ~= filler(10);
			}

			// build gui for tubes that can be loaded on spawn
			foreach (const AmmoRoomTemplate ammoRoom; subTmpl.ammoRooms)
			{
				TubeTemplate[] roomTubes = cast(TubeTemplate[]) subTmpl.tubes.filter!(
					tt => tt.roomId == ammoRoom.id && tt.loadedOnSpawn).array;
				if (roomTubes.length == 0)
					continue;
				roomTubes.sort!("a.id < b.id");
				Label roomHeader = builder(new Label()).content(ammoRoom.name ~ " tubes").
					fontSize(BTN_FONT).fontColor(COLORS.loadoutHint).fixedSize(vec2i(1, 30)).build;
				divElements ~= roomHeader;
				foreach (const TubeTemplate tt; roomTubes)
				{
					tubeLoadouts[tt.id] = ammoRoom.allowedWeaponSet.weaponNames[0];
					divElements ~= buildTubeLoadDiv(tt.id, tubeLoadouts[tt.id],
						ammoRoom.allowedWeaponSet.weaponNames);
				}
				divElements ~= filler(10);
			}

			// build scrollable div that combines propulsors, racks and tubes
			int totalDivHeight = divElements.map!(e => e.size.y + 2).sum();
			Div combinedDiv = builder(vDiv(divElements)).borderWidth(2).
				fixedSize(vec2i(200, totalDivHeight)).build;
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
		Hull1 |	Description	| hull_props
		Hull2 |				| racks
		Hull3 |				| tubes
			  |				| Play
		*/

		hullDescriptionBox = new TextBox();
		hullDescriptionBox.fontSize = 16;

		// scrollist of available hulls
		Button[] hullButtons;
		foreach (i, hullname; availableHulls)
		{
			Button hullSelector = builder(new Button()).content(hullname).
				fontSize(BTN_FONT).fixedSize(vec2i(200, BTN_SIZE)).
				htextAlign(HTextAlign.LEFT).build();
			hullButtons ~= hullSelector;
			hullSelector.onClick += ((string hn) => { selectHull(hn); })(hullname);
			hullSelector.onClick += ((Button selectedBtn) => {
					selectedBtn.fontColor = COLORS.textFieldCursor;
					hullButtons.filter!(b => b !is selectedBtn).
						each!(b => b.fontColor = COLORS.defaultFont);
				})(hullSelector);
			auto capture = (string hn) =>
				(IInputReceiver obj)
				{
					hullDescriptionBox.content =
						Game.entityManager.submarineTemplates[hn].description;
				};
			hullSelector.onMouseEnter += capture(hullname);
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

		Div hullDiv = builder(vDiv(cast(GuiElement[]) hullButtons)).
			layoutType(LayoutType.CONTENT).
			size(vec2i(200, BTN_SIZE * availableHulls.length.to!int +
							availableHulls.length.to!int)).build;
		ScrollBar hullsScrollbar = new ScrollBar(hullDiv);

		startButton = builder(new Button(ButtonType.ASYNC)).fontSize(45).
			htextAlign(HTextAlign.CENTER).content("Start").fixedSize(vec2i(1, 70)).
			backgroundColor(COLORS.simLaunchButtonBgnd).fontColor(sfBlack).
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
						)).array,
					tubeLoadouts.byKeyValue.map!(pair =>
						TubeSpawnState(pair.key, pair.value)).array,
					SpawnRequestType.existingSimulator,
					"main_arena"
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
							fontSize(BTN_FONT).fontColor(COLORS.loadoutHint).
							fixedSize(vec2i(1, 30)).build,
						hullsScrollbar
					])
				).fixedSize(vec2i(150, 1)).build(),
			filler(20),
			vDiv([
				builder(new Label()).fontSize(BTN_FONT).
					fixedSize(vec2i(1, BTN_SIZE)).fontColor(COLORS.loadoutHint).
					content("Description").build,
				new ScrollBar(hullDescriptionBox)
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

	// shared by loginscreen and this state
	static void handleReconnectStateRes(ReconnectStateRes res)
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
		// CIC client will perform simulator bootstrap from here, will broadcast
		// reconnect message to cic clients, and this window's cic client will
		// switch game state to Simulator.
		Game.cic.handleReconnectStateRes(res);
	}

	void handleSpawnFailureRes(SpawnFailureRes res)
	{
		hullDescriptionBox.content = "Spawn failed: " ~ res.reason;
		startButton.signalClickEnd();
	}

}