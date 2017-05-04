module dsubs_client.tests;

import std.experimental.logger;

import dsubs_client.core.sfml;
import dsubs_client.core.window;
import dsubs_client.render.render;
import dsubs_client.gui.manager;
import dsubs_client.gui.element;
import dsubs_client.gui.div;
import dsubs_client.gui.label;
import dsubs_client.gui.button;
import dsubs_client.input.router;


void test_window()
{
	info("test_window...");
	loadSfmlLibraries();
	Window wnd = new Window();
	wnd.poll_events();
	info("OK");
}

void test_render()
{
	info("test_window...");
	loadSfmlLibraries();
	Window wnd = new Window();
	Render render = new Render(wnd);
	wnd.register_handler(sfEvtClosed, (const sfEvent* a) { render.stop(); });
	render.start();
	wnd.poll_events();
	info("OK");
}

void test_div_render()
{
	info("test_div_render...");
	loadSfmlLibraries();
	Window wnd = new Window();
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
	wnd.poll_events();
	info("OK");
}


void test_menu_layout()
{
	info("test_menu_layout...");
	loadSfmlLibraries();
	Window wnd = new Window();
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
	wnd.poll_events();
	info("OK");
}


void test_menu_routing()
{
	info("test_menu_routing...");
	loadSfmlLibraries();
	Window wnd = new Window();
	Render render = new Render(wnd);
	wnd.register_handler(sfEvtClosed, (const sfEvent* a) { render.stop(); });
	GuiManager mgr = new GuiManager();
	Button exitBtn = new Button(mgr).content("Exit").font_size(20).asButton;
	VDiv menu =
		new VDiv(mgr,
			new Label(mgr).content("DSUBS").font_size(40).sizeType(SizeType.FIXED).
				size(vec2f(0.0f, 100.0f)),
			new Label(mgr).content("Connect").font_size(20),
			new Label(mgr).content("Options").font_size(20),
			exitBtn,
		).sizeType(SizeType.FIXED).size(vec2f(300, 0)).asVdiv;
	auto panel =
		new VDiv(mgr,
			new GuiElement(mgr),
			new HDiv(mgr,
				new GuiElement(mgr),
				menu,
				new GuiElement(mgr),
			).sizeType(SizeType.FIXED).size(vec2f(0, 250)),
			new GuiElement(mgr),
		).sizeType(SizeType.FIXED).size(vec2f(wnd.width, wnd.height));
	mgr.addAsPanel(panel);
	wnd.register_handler(sfEvtResized,
		(const sfEvent* a) {panel.size(vec2f(a.size.width, a.size.height));});
	render.gui_render = mgr;
	// events
	Router router = new Router(wnd);
	router.gui_router = mgr;
	foreach (lbl; menu.children)
	{
		Label l = lbl.asLabel;
		log("Registering ", l.content);
		auto captureEnter(Label l)
		{
			return (GuiElement s)
				{
					log("Enter ", l.content);
					l.font_color(sfColor(255, 150, 150, 255));
				};
		}
		auto captureLeave(Label l) { return (GuiElement s){log("Leave ", l.content); l.font_color(sfWhite);};}
		l.onMouseEnter += captureEnter(l);
		l.onMouseLeave += captureLeave(l);
	}
	exitBtn.onClick += (Button s, sfMouseButton btn) { log("Clicked ", s.content); };
	exitBtn.onClick += (Button s, sfMouseButton btn) { wnd.close_window(); };
	// go
	render.start();
	wnd.poll_events();
	info("OK");
}
