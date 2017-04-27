module dsubs_client.app;

import std.experimental.logger;

import dsubs_client.core.sfml;
import dsubs_client.core.window;


int main(string[] argv)
{
	info("Starting Dsubs client");
	loadSfmlLibraries();
	Window wnd = new Window();
	bool close = false;
	wnd.register_handler(sfEvtClosed, (const sfEvent* a) { close = true; });
	while (!close)
		wnd.poll_events();
	log("Window was closed, termitating application");
	return 0;
}
