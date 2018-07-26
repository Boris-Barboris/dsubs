module dsubs_client.game;

import std.parallelism;

import core.sync.mutex;
import core.thread;
import core.memory: GC;

import dsubs_common.api;
import dsubs_common.api.protocols.backend: EntityDbRes;

import dsubs_client.common;
import dsubs_client.core.scheduler;
import dsubs_client.core.window;
import dsubs_client.input.router;
import dsubs_client.input.hotkeymanager;
import dsubs_client.gui.manager;
import dsubs_client.render.render;
import dsubs_client.render.worldmanager;

import dsubs_client.game.gamestate;
import dsubs_client.game.connections.backend;
import dsubs_client.game.entities;
import dsubs_client.game.cic.server;
import dsubs_client.game.states.mainmenu;
import dsubs_client.game.states.loadout;
import dsubs_client.game.states.simulation;


/// Namespace for globals wich represent the game state.
class Game
{
__gshared:
	bool shuttingDown;

	Window window;
	InputRouter inputRouter;
	Render render;
	GuiManager guiManager;
	WorldManager worldManager;
	HotkeyManager hotkeyManager;
	Scheduler scheduler;

	/// Global lock, held by window message pump and render threads.
	/// When in doubt, hold this one.
	Mutex mainMutex;

	// entity databases in different forms
	immutable(ubyte)[] entityDbHash;
	EntityDbRes entityDb;
	EntityManager entityManager;

	/// persistent backend connection
	BackendConMaintainer bconm;

	/// CIC
	CICServer cic;
	CICClientConnection ciccon;

	private GameState m_activeState;

	/// get current active game state object
	static @property GameState activeState() { return m_activeState; }

	/// switch game to new state
	static @property void activeState(GameState newState)
	{
		assert(newState);
		if (shuttingDown)
			return;
		if (m_activeState)
			info("STATE TRANSITION: " ~ m_activeState.kind.to!string ~ " to ",
				newState.kind.to!string);
		clearEntities();
		m_activeState = newState;
		m_activeState.setup();
	}

	static @property MainMenuState mainMenuState()
	{
		enforce(m_activeState.kind == GameStateKind.MAINMENU,
			"game is not in main menu state, but in " ~ m_activeState.kind.to!string);
		return cast(MainMenuState) m_activeState;
	}

	static @property LoadoutState loadoutState()
	{
		enforce(m_activeState.kind == GameStateKind.LOADOUT,
			"game is not in loadout state, but in " ~ m_activeState.kind.to!string);
		return cast(LoadoutState) m_activeState;
	}

	static @property SimulatorState simState()
	{
		enforce(m_activeState.kind == GameStateKind.SIMULATION,
			"game is not in simulator state, but in " ~ m_activeState.kind.to!string);
		return cast(SimulatorState) m_activeState;
	}

	/// start the game (blocks caller thread)
	static void start()
	{
		assert(window is null);
		window = new Window();
		inputRouter = new InputRouter(window);
		render = new Render(window, inputRouter);
		guiManager = new GuiManager(window);
		worldManager = new WorldManager(window);
		hotkeyManager = new HotkeyManager(window);
		mainMutex = new Mutex();
		scheduler = new Scheduler();
		scheduler.start();
		scope(failure) scheduler.stop();
		render.guiRender = guiManager;
		render.worldRender = worldManager;
		inputRouter.guiRouter = guiManager;
		inputRouter.worldRouter = worldManager;
		inputRouter.hotkeyRouter = hotkeyManager;

		// start connection maintainer
		bconm = new BackendConMaintainer();
		scope(exit)
		{
			// connection cleanup
			info("shutting down TCP connections...");
			bconm.stop();
			if (ciccon)
				ciccon.close();
			if (cic)
				cic.stop();
		}

		// setup main menu
		synchronized (mainMutex)
			activeState = new MainMenuState();

		// start render thread and serve the windows event pump
		render.start(mainMutex);
		scope(failure)
		{
			shuttingDown = true;
			render.stop();
		}
		window.pollEvents(mainMutex);
		shuttingDown = true;
		scheduler.stop();
		render.stop();
		window.close();
	}

	/// clear various callbacks and objects in order to transition to another
	/// game state.
	private static void clearEntities()
	{
		inputRouter.clearFocused();
		guiManager.clearPanels();
		render.clearHandlers();
		worldManager.clear();
		hotkeyManager.clear();
		// let's free some memory after the clear
		delay(() { GC.collect(); }, msecs(500));
		// hotkey manager requires some additional attention
		render.onPreRender += (long usecs) { hotkeyManager.processHeldKeys(usecs); };
	}

	/// execute delegate 'what' after 'after' time interval, while holding
	/// 'mutToHold' lock.
	static void delay(void delegate() what, Duration after,
		Mutex mutToHold = Game.mainMutex)
	{
		assert(Game.scheduler !is null);
		Game.scheduler.delay(what, after, mutToHold);
	}
}