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
import dsubs_client.gui.textbox;
import dsubs_client.gui.textfield;
import dsubs_client.gui.passwordfield;
import dsubs_client.gui.scrollbar;
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
	render.preRender += (s) { router.simulate_mouse_move(); };

	dstring testtext =
"Says old Harte to his missis
O what do I see?
Bold Sophie's commander
With his fiddle-dee-dee.

James Dillon would never have allowed it, but Mr Daiziel had no notion of any of the allusions and the song went on and on until the cable was all below in tiers, smelling disagreeably of Mahon ooze, and the Sophie was hoisting her jibs and bracing her foretopsailyard round. She dropped down abreast of the Amelia, whom she had not seen since the action with the Cacafuego, and all at once Mr Daiziel observed that the frigate's rigging was full of men, all carrying their hats and facing the Sophie.

'Mr Babbington,' he said in a low voice, in case he should be mistaken, for he had only seen this happen once before, 'tell the captain, with my duty, that I believe Amelia is going to cheer us.'
Jack came blinking on deck as the first cheer roared out, a shattering wave of sound at twenty-five yards' range. Then came the Amelia's bosun's pipe and the next cheer, as precisely timed as her own broadside: and the third. He and his officers stood rigidly with their hats off, and as soon as the last roar had died away over the harbour, echoing back and forth, he called out, 'Three cheers for the Amelia!' and the Sophies, though deep in the working of the sloop, responded like heroes, scarlet with pleasure and the energy needed f or huzzaying proper – huge energy, for they knew what was manners. Then the Amelia, now far astern, called 'One cheer more,' and so piped down.
It was a handsome compliment, a noble send-off, and it gave great pleasure: but still it did not prevent the Sophies from feeling a strong sense of grievance – it did not prevent them from calling out 'Give us back our thirty-seven days' as a sort of slogan or watchword between decks, and even above hatches when they dared – it did not wholly recall them to their duty, and in the following days and weeks they were more than ordinarily tedious.
The brief interlude in Port Mahon harbour had been exceptionally bad for discipline. One of the results of their fierce contraction into a single defiant ill-used body was that the hierarchy (in its finer shades) had for a time virtually disappeared; and among other things the ship's corporal had let the wounded men returning to their duty bring in bladders and skins full of Spanish brandy, anisette and a colourless liquid said to be gin. A discreditable number of men had succumbed to its influence, among them the captain of the foretop (paralytic) and both bosun's mates. Jack disrated Morgan, promoting the dumb negro Alfred King, according to his former threat – a dumb bosun's mate would surely be more terrible, more deterrent; particularly one with such a very powerful arm.
"d;

	Button exitBtn = new Button(mgr).content("Exit").font_size(20).asButton;
	VDiv menu =
		new VDiv(mgr,
			new Label(mgr).content("DSUBS").font_size(40).sizeType(SizeType.FIXED).
				size(vec2f(0.0f, 100.0f)),
			new Label(mgr).content("Connect").font_size(20),
			new TextField(mgr).font_size(20),
			new PasswordField(mgr).font_size(16),
			exitBtn,
		).sizeType(SizeType.FIXED).size(vec2f(300, 0)).asVdiv;
	auto panel =
		new VDiv(mgr,
			new GuiElement(mgr),
			new HDiv(mgr,
				new ScrollBar!TextBox(mgr,
					new TextBox(mgr).font_size(12).content(testtext)),
				menu,
				new GuiElement(mgr),
			).sizeType(SizeType.FIXED).size(vec2f(0, 350)),
			new GuiElement(mgr),
		).size(vec2f(wnd.width, wnd.height));
	mgr.addAsPanel(panel);
	// events
	foreach (lbl; menu.children)
	{
		Label l = lbl.asLabel;
		if (l)
		{
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
		ConvexShape shape;
		this(WorldManager manager)
		{
			super(manager);
			shape = new ConvexShape(
				[sfVector2f(60.0f, 0.0f), sfVector2f(0.0f, 100.0f),
				 sfVector2f(-60.0f, 0.0f), sfVector2f(0.0f, -100.0f)],
				sfColor(255, 150, 150, 50),
				sfWhite,
				5.0f);
			last_update = MonoTime.currTime;
		}

		override void render(Window wnd)
		{
			shape.render(wnd, transform.sfglobal);
		}

		private MonoTime last_update;

		override void update_transform()
		{
			MonoTime cur = MonoTime.currTime;
			auto diff = (cur - last_update).total!"msecs";
			transform.rotation = transform.rotation + diff * 3e-4;
			last_update = cur;
			ctx.camera.center(ctx.camera.center + diff * vec2d(-0.05, 0.0));
		}
	}

	mgr.addRoot(new BoxModel(mgr));
	ctx.camera.center(vec2d(100.0, 50.0));
	ctx.camera.zoom(2.0);
	ctx.camera.rotation(0.15);
	// go
	render.start();
	wnd.poll_events();
	info("OK");
}
