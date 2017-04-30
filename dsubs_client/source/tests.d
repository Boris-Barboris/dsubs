module dsubs_client.tests;

import std.experimental.logger;

import dsubs_client.core.sfml;
import dsubs_client.core.window;
import dsubs_client.render.render;
import dsubs_client.gui.manager;
import dsubs_client.gui.element;
import dsubs_client.gui.label;


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
			new Label(mgr).content("div1"),
			new Label(mgr).content("div2").font_size(20).fontname("Sans").vert_align(TextAlign.LEFT)
		).sizeType(SizeType.FIXED).size(vec2f(400, 200));
	mgr.addAsPanel(div);
	render.gui_render = mgr;
	render.start();
	while (!close)
		wnd.poll_events();
	wnd.close_window();
	info("OK");
}


void test_menu_layout()
{
	info("test_menu_layout...");
	loadSfmlLibraries();
	Window wnd = new Window();
	bool close = false;
	wnd.register_handler(sfEvtClosed, (const sfEvent* a) { close = true; });
	Render render = new Render(wnd);
	wnd.register_handler(sfEvtClosed, (const sfEvent* a) { render.stop(); });
	GuiManager mgr = new GuiManager();
	auto menu =
		new VDiv(mgr,
			new GuiElement(mgr),
			new VDiv(mgr,
				new Label(mgr).content("DSUBS").font_size(40).sizeType(SizeType.FIXED).
					size(vec2f(0.0f, 100.0f)),
				new Label(mgr).content("Connect").font_size(20),
				new Label(mgr).content("Options").font_size(20),
				new Label(mgr).content("Exit").font_size(20)
				).sizeType(SizeType.FIXED).size(vec2f(0.0, 250.0)),
			new GuiElement(mgr),
		).sizeType(SizeType.FIXED).size(vec2f(wnd.width, wnd.height));
	mgr.addAsPanel(menu);
	wnd.register_handler(sfEvtResized,
		(const sfEvent* a) {menu.size(vec2f(a.size.width, a.size.height));});
	render.gui_render = mgr;
	render.start();
	while (!close)
		wnd.poll_events();
	wnd.close_window();
	info("OK");
}
