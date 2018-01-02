module dsubs_client.game;

import core.sync.mutex;

import std.experimental.logger;
import std.parallelism;

import dsubs_client.core.window;
import dsubs_client.input.router;
import dsubs_client.gui.manager;
import dsubs_client.render.render;
import dsubs_client.render.manager;

import dsubs_client.game.connection;
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

	/// global lock, held by window message pump and render threads
	Mutex mainMutex;

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
		render.guiRender = guiManager;
		render.worldRender = worldManager;
		inputRouter.guiRouter = guiManager;
		inputRouter.worldRouter = worldManager;
		serverConnection = new ServerConnection("localhost", mainMutex);
		scope (failure) serverConnection.close();

		setupMainMenu();
		render.start(mainMutex);
		window.pollEvents(mainMutex);
		render.stop();
		serverConnection.close();
		window.close();
	}

	static void clearEntities()
	{
		serverConnection.clearHandlers();
		guiManager.clearPanels();
		worldManager.components.clear();
	}
}