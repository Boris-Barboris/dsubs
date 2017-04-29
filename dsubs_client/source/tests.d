module dsubs_client.tests;

import std.experimental.logger;

import dsubs_client.core.sfml;
import dsubs_client.core.window;
import dsubs_client.render.render;


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
