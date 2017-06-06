module dsubs_client.tests;

import std.experimental.logger;
import std.utf;

import dsubs_client.core.sfml;
import dsubs_client.core.window;
import dsubs_client.render.render;
import dsubs_client.gui.manager;
import dsubs_client.gui.element;
import dsubs_client.gui.div;
import dsubs_client.gui.label;
import dsubs_client.gui.button;
import dsubs_client.gui.textfield;
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
	GuiManager mgr = new GuiManager();
	render.gui_render = mgr;
	router.gui_router = mgr;
	render.postRender += (s) { router.simulate_mouse_move(); };
	Button exitBtn = new Button(mgr).content("Exit").font_size(20).asButton;
	VDiv menu =
		new VDiv(mgr,
			new Label(mgr).content("DSUBS").font_size(40).sizeType(SizeType.FIXED).
				size(vec2f(0.0f, 100.0f)),
			new Label(mgr).content("Connect").font_size(20),
			new TextField(mgr).font_size(20),
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
				l.font_size(l.font_size + 3);
			};
		}
		auto captureLeave(Label l)
		{
			return (GuiElement s)
			{
				log("Leave ", l.content);
				l.font_color(sfWhite);
				l.font_size(l.font_size - 3);
			};
		}
		l.onMouseEnter += captureEnter(l);
		l.onMouseLeave += captureLeave(l);
	}
	exitBtn.onClick += (Button s, sfMouseButton btn)
		{ log("Clicked ", s.content); };
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
	Router router = new Router(wnd);
	WorldManager mgr = new WorldManager();
	router.world_router = mgr;
	render.world_render = mgr;
	auto ctx = mgr.generate_context(wnd);
	// some example class, rotating box

	import core.time;
	import dsubs_common.math.transform;
	import dsubs_client.core.sfml;

	class BoxModel: WorldRenderable
	{
		Transform2D transform;
		ConvexShape shape;
		this(WorldManager manager)
		{
			super(manager);
			transform = new Transform2D();
			shape = new ConvexShape(
				[sfVector2f(100.0f, 0.0f), sfVector2f(0.0f, 100.0f),
				 sfVector2f(-100.0f, 0.0f), sfVector2f(0.0f, -100.0f)],
				sfColor(255, 150, 150, 50),
				sfWhite,
				5.0f);
			last_update = MonoTime.currTime;
		}

		override void render(Window wnd)
		{
			shape.render(wnd, transform.global.tosf);
		}

		private MonoTime last_update;

		override void update_transform()
		{
			MonoTime cur = MonoTime.currTime;
			auto diff = (cur - last_update).total!"msecs";
			transform.rotation = transform.rotation + diff * 3e-4;
			last_update = cur;
		}
	}

	mgr.addRoot(new BoxModel(mgr));
	ctx.camera.center(vec2d(0, 50.0));
	ctx.camera.zoom(2.0);
	ctx.camera.rotation(0.15);
	// go
	render.start();
	wnd.poll_events();
	info("OK");
}
