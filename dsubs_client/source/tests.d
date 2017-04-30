module dsubs_client.tests;

import std.experimental.logger;

import dsubs_client.core.sfml;
import dsubs_client.core.window;
import dsubs_client.render.render;
import dsubs_client.gui.manager;
import dsubs_client.gui.element;


void test_window()
{
	info("test_window...");
	loadSfmlLibraries();
	Window wnd = new Window();
	bool close = false;
	wnd.register_handler(sfEvtClosed, (const sfEvent* a) { close = true; });
	while (!close)
		wnd.poll_events();
	wnd.close_window();
	info("OK");
}

void test_render()
{
	info("test_window...");
	loadSfmlLibraries();
	Window wnd = new Window();
	bool close = false;
	wnd.register_handler(sfEvtClosed, (const sfEvent* a) { close = true; });
	Render render = new Render(wnd);
	wnd.register_handler(sfEvtClosed, (const sfEvent* a) { render.stop(); });
	render.start();
	while (!close)
		wnd.poll_events();
	wnd.close_window();
	info("OK");
}

void test_div_render()
{
	info("test_div_render...");
	loadSfmlLibraries();
	Window wnd = new Window();
	bool close = false;
	wnd.register_handler(sfEvtClosed, (const sfEvent* a) { close = true; });
	Render render = new Render(wnd);
	wnd.register_handler(sfEvtClosed, (const sfEvent* a) { render.stop(); });
	GuiManager mgr = new GuiManager();
	auto div =
		new HDiv(mgr,
			new GuiElement(mgr),
			new GuiElement(mgr)
		).sizeType(SizeType.FIXED).size(vec2f(400, 200));
	mgr.addAsPanel(div);
	render.gui_render = mgr;
	render.start();
	while (!close)
		wnd.poll_events();
	wnd.close_window();
	info("OK");
}
