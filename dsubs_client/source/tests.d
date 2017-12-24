module dsubs_client.tests;

import core.sync.mutex;

import std.conv: to;
import std.math: abs;
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
	
	Div row1 = builder(hDiv(
		[
			builder(new Label()).content("RED").fontSize(32).backgroundVisible(true).
				backgroundColor(sfColor(255, 0, 0, 255)).fontColor(sfBlack).
				htextAlign(HTextAlign.LEFT).vtextAlign(VTextAlign.TOP).build(),

			builder(new Label()).content("GREEN").fontSize(32).backgroundVisible(true).
				backgroundColor(sfColor(0, 255, 0, 255)).fontColor(sfBlack).
				htextAlign(HTextAlign.CENTER).vtextAlign(VTextAlign.CENTER).build(),

			builder(new Label()).content("BLUE").fontSize(32).backgroundVisible(true).
				backgroundColor(sfColor(0, 0, 255, 255)).fontColor(sfBlack).
				htextAlign(HTextAlign.RIGHT).vtextAlign(VTextAlign.BOTTOM).build()
		]
	)).borderWidth(5).build();

	Div row2 = builder(hDiv(
		[
			builder(new TextField()).fontSize(46).content("TextField").build(),
			builder(new PasswordField()).fontSize(28).content("TextField").build(),
			builder(new TextField()).fontSize(14).content("TextField").build()
		]
	)).borderWidth(5).build();

	auto label1 = builder(new Label()).fontSize(32).build();
	int btn1Counter = 0;
	int shiftDir = 1;
	auto button1 = builder(new Button(ButtonType.SYNC)).fontSize(32).
		content("Click me").build();
	button1.onClick += (btn)
	{
		if (btn == sfMouseLeft)
			btn1Counter += shiftDir;
		if (btn == sfMouseRight)
			btn1Counter -= shiftDir;
		label1.content = btn1Counter.to!string; 
	};
	auto button2 = builder(new Button(ButtonType.TOGGLE)).fontSize(32).
		content("Positive").build();
	button2.onClick += (btn) {
		if (button2.state == ButtonState.ACTIVE)
		{
			button2.content = "Negative";
			shiftDir = -abs(shiftDir);
		}
		else
		{
			button2.content = "Positive";
			shiftDir = abs(shiftDir);
		}
	};
	auto button3 = builder(new Button(ButtonType.ASYNC)).fontSize(24).
		content("Activate x10").build();
	auto button4 = builder(new Button(ButtonType.SYNC)).fontSize(24).
		content("Deactivate x10").build();
	button3.onClick += (btn) 
	{
		shiftDir *= 10;
	};
	button4.onClick += (btn)
	{
		if (button3.state == ButtonState.ACTIVE)
		{
			button3.signalClickEnd();
			shiftDir /= 10;
		}
	};

	Div row3 = builder(hDiv(
		[
			label1,
			button1,
			button2,
			builder(vDiv([button3, button4])).borderWidth(3).build()
		]
	)).borderWidth(5).build();

	Div guiDemoRoot = vDiv(
		[
			row1,
			row2,
			row3
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