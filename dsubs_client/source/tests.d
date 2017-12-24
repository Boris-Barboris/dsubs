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
	
	Div semaphore = builder(hDiv(
		[
			builder(new Label()).content("RED").fontSize(32).
				backgroundColor(sfColor(255, 0, 0, 255)).fontColor(sfBlack).
				htextAlign(HTextAlign.LEFT).vtextAlign(VTextAlign.TOP).build(),

			builder(new Label()).content("GREEN").fontSize(32).
				backgroundColor(sfColor(0, 255, 0, 255)).fontColor(sfBlack).
				htextAlign(HTextAlign.CENTER).vtextAlign(VTextAlign.CENTER).build(),

			builder(new Label()).content("BLUE").fontSize(32).
				backgroundColor(sfColor(0, 0, 255, 255)).fontColor(sfBlack).
				htextAlign(HTextAlign.RIGHT).vtextAlign(VTextAlign.BOTTOM).build()
		]
	)).borderWidth(5).build();
	Div guiDemoRoot = vDiv(
		[
			semaphore,
			new GuiElement()
		]);
	guiDemoRoot.borderWidth = 5;
	gui.addPanel(new Panel(guiDemoRoot));

	Mutex mutex = new Mutex();
	render.start(mutex);
	wnd.pollEvents(mutex);
	render.stop();
	wnd.close();
	info("OK");
}