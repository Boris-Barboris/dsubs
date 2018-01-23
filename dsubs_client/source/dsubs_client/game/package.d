module dsubs_client.game;

import std.experimental.logger;
import std.parallelism;

import core.sync.mutex;
import core.thread;

import dsubs_common.api;

import dsubs_client.core.delayer;
import dsubs_client.core.window;
import dsubs_client.input.router;
import dsubs_client.gui.manager;
import dsubs_client.render.render;
import dsubs_client.render.manager;

import dsubs_client.game.connection;
public import dsubs_client.game.entities;
import dsubs_client.game.mainmenu;


/// Namespace for globals wich represent the game state.
class Game
{
__gshared:
	Window window;
	InputRouter inputRouter;
	Render render;
	GuiManager guiManager;
	WorldManager worldManager;
	ServerConnection serverConnection;
	Delayer delayer;

	/// Global lock, held by window message pump and render threads.
	/// When in doubt, lock this one.
	Mutex mainMutex;

	// entity databases in different forms
	EntityDbRes entityDb;
	EntityManager entityManager;

	/// start the game
	static void start()
	{
		assert(window is null);
		window = new Window();
		inputRouter = new InputRouter(window);
		render = new Render(window, inputRouter);
		guiManager = new GuiManager(window);
		worldManager = new WorldManager(window);
		mainMutex = new Mutex();
		delayer = new Delayer();
		scope(failure) delayer.stop();
		render.guiRender = guiManager;
		render.worldRender = worldManager;
		inputRouter.guiRouter = guiManager;
		inputRouter.worldRouter = worldManager;
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

	static void clearEntities()
	{
		serverConnection.clearHandlers();
		inputRouter.clearFocused();
		guiManager.clearPanels();
		worldManager.components.clear();
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