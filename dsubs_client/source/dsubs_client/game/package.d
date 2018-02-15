module dsubs_client.game;

import std.experimental.logger;
import std.parallelism;

import core.sync.mutex;
import core.thread;
import core.memory: GC;

import dsubs_common.api;

import dsubs_client.core.delayer;
import dsubs_client.core.window;
import dsubs_client.input.router;
import dsubs_client.input.hotkeymanager;
import dsubs_client.gui.manager;
import dsubs_client.render.render;
import dsubs_client.render.worldmanager;

import dsubs_client.game.connection;
import dsubs_client.game.simulation;
public import dsubs_client.game.entities;
public import dsubs_client.game.mainmenu;


/// Namespace for globals wich represent the game state.
class Game
{
__gshared:
	Window window;
	InputRouter inputRouter;
	Render render;
	GuiManager guiManager;
	WorldManager worldManager;
	HotkeyManager hotkeyManager;
	ServerConnection serverConnection;
	Delayer delayer;

	/// Global lock, held by window message pump and render threads.
	/// When in doubt, lock this one.
	Mutex mainMutex;

	// entity databases in different forms
	EntityDbRes entityDb;
	EntityManager entityManager;

	/// simulator state
	SimulatorState simState;

	/// start the game
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
		delayer = new Delayer();
		scope(failure) delayer.stop();
		render.guiRender = guiManager;
		render.worldRender = worldManager;
		inputRouter.guiRouter = guiManager;
		inputRouter.worldRouter = worldManager;
		inputRouter.hotkeyRouter = hotkeyManager;
		serverConnection = new ServerConnection("127.0.0.1", mainMutex);
		scope (failure) serverConnection.close();

		// setup main menu
		synchronized (mainMutex)
			setupMainMenu();
		// start render thread and serve the windows event pump
		render.start(mainMutex);
		window.pollEvents(mainMutex);

		delayer.stop();
		render.stop();
		serverConnection.close();
		window.close();
		// give time to all background threads to acknowledge shutdown
		Thread.sleep(msecs(100));
	}

	/// clear various callbacks and objects in order to transition to another
	/// game state.
	static void clearEntities()
	{
		serverConnection.clearHandlers();
		inputRouter.clearFocused();
		guiManager.clearPanels();
		render.clearHandlers();
		worldManager.clear();
		hotkeyManager.clear();
		Game.simState = null;
		// let's free some unneeded resources
		GC.collect();
		// hotkey manager requires some additional attention
		render.onPreRender += (long usecs) { hotkeyManager.processHeldKeys(usecs); };
	}

	/// execute delegate 'what' after 'after' time interval, while holding
	/// 'mutToHold' lock.
	static void delay(void delegate() what, Duration after,
		Mutex mutToHold = Game.mainMutex)
	{
		assert(Game.delayer !is null);
		Game.delayer.delay(what, after, mutToHold);
	}
}