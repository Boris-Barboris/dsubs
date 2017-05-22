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
	Router router = new Router(wnd);
	GuiManager mgr = new GuiManager(wnd, router);
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
		auto captureLeave(Label l)
		{
			return (GuiElement s)
			{
				log("Leave ", l.content);
				l.font_color(sfWhite);
			};
		}
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

import dsubs_client.world.camera;
import dsubs_client.world.convex;
import dsubs_client.world.manager;

void test_world_manager_simple()
{
	info("test_world_manager_simple...");
	loadSfmlLibraries();
	Window wnd = new Window();
	Render render = new Render(wnd);
	WorldManager mgr = new WorldManager();
	render.world_render = mgr;
	Camera2D camera = new Camera2D(vec2ui(wnd.width, wnd.height));
	wnd.register_handler(sfEvtResized,
		(const sfEvent* a) {camera.screen_size(vec2ui(a.size.width, a.size.height));});
	mgr.cameras[wnd] = camera;
	// some example class, rotating box

	import core.time;

	class BoxModel: WorldRenderable
	{
		ConvexShape shape;
		this(WorldManager manager)
		{
			super(manager);
			shape = new ConvexShape(
				[sfVector2f(100.0f, 0.0f), sfVector2f(0.0f, 100.0f),
				 sfVector2f(-100.0f, 0.0f), sfVector2f(0.0f, -100.0f)],
				sfColor(255, 150, 150, 50),
				sfWhite,
				5.0f);
			transform.add_child(shape.transform);
			last_update = MonoTime.currTime;
		}

		override void render(Window wnd, const(mat3x3d)* mat)
		{
			shape.render(wnd, mat);
		}

		private MonoTime last_update;

		override void update_transform()
		{
			MonoTime cur = MonoTime.currTime;
			auto diff = (cur - last_update).total!"msecs";
			transform.rotation = transform.rotation + diff * 1e-3;
			last_update = cur;
		}
	}

	mgr.addRoot(new BoxModel(mgr));
	// go
	render.start();
	wnd.poll_events();
	info("OK");
}
