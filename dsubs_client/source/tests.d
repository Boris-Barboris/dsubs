module dsubs_client.tests;

import core.sync.mutex;

import std.experimental.logger;

import derelict.sfml2.graphics;

import dsubs_client.core.window;
import dsubs_client.core.utils;
import dsubs_client.input.router;
import dsubs_client.render.render;
import dsubs_client.gui;

import dsubs_client.world.camera;


void runModuleTests()
{
	testCamera2D();
}

void testGuiElements()
{
	info("testGuiElements...");
	Window wnd = new Window("dsubs testGuiElements"d);
	InputRouter router = new InputRouter(wnd);
	GuiManager gui = new GuiManager(wnd);
	router.guiRouter = gui;
	Render render = new Render(wnd, router);
	render.guiRender = gui;
	
	HDiv guiDemo = builder(new HDiv(
		[
			builder(new GuiElement()).backgroundVisible(true).backgroundColor(sfColor(255, 0, 0, 255)).build(),
			builder(new GuiElement()).backgroundVisible(true).backgroundColor(sfColor(0, 255, 0, 255)).build(),
			builder(new GuiElement()).backgroundVisible(true).backgroundColor(sfColor(0, 0, 255, 255)).build()
		]
	)).layoutType(LayoutType.GREEDY).borderWidth(5).build();
	gui.addPanel(new Panel(guiDemo));

	Mutex mutex = new Mutex();
	render.start(mutex);
	wnd.pollEvents(mutex);
	render.stop();
	wnd.close();
	info("OK");
}