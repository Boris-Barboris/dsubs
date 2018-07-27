module dsubs_client.game.states.simulation;

import std.algorithm;
import std.array;
import std.conv: to;
import std.format;
import std.math;
import std.experimental.logger;

import core.thread;

import derelict.sfml2.window;

import dsubs_common.api;
import dsubs_common.api.protocols.backend;
import dsubs_common.math;

import dsubs_client.core.utils;
import dsubs_client.game;
import dsubs_client.gui;
import dsubs_client.input.hotkeymanager;
import dsubs_client.game.gamestate;
import dsubs_client.game.entities;
import dsubs_client.game.states.mainmenu;
import dsubs_client.game.cic.server;
import dsubs_client.game.cic.messages;
import dsubs_client.game.cameracontroller;
import dsubs_client.game.overlay;



final class SimulatorState: GameState
{
	this(CICReconnectStateRes recState)
	{
		super(GameStateKind.SIMULATION);
		this.recState = recState;
	}

	private
	{
		CICReconnectStateRes recState;
	}

	mixin Readonly!(Submarine, "playerSub");
	mixin Readonly!(CameraController, "camController");
	mixin Readonly!(SimulationGUI, "gui");

	override void setup()
	{
		// create submarine
		m_playerSub = new Submarine(
			Game.entityManager, recState.submarineName, recState.propulsorName);
		m_playerSub.targetCourse = recState.targetCourse;
		m_playerSub.targetThrottle = recState.targetThrottle;
		m_playerSub.updateKinematics(recState.subSnap);
		Game.worldManager.components ~= m_playerSub;

		// set up camera
		Game.worldManager.camCtx.camera.center = recState.subSnap.position.toGfm;
		Game.worldManager.camCtx.camera.zoom = 10.0;
		m_camController = new CameraController();
		Game.worldManager.mouseReceivers ~= m_camController;

		m_gui = new SimulationGUI();
		Game.worldManager.components ~= new PlayerSubIcon(m_playerSub);
	}

	override void handleBackendDisconnect()
	{
		Game.activeState = new MainMenuState();
	}

	override void handleCICDisconnect()
	{
		error("CIC connection lost");
		Game.activeState = new MainMenuState();
	}
}


private
{
	enum int TAB_SIZE = 28;
	enum int BIG_BTN_FONT = 25;
	enum int BTN_FONT = 20;
	enum sfColor HINT_COLOR = sfColor(150, 150, 150, 255);
	enum sfColor DIV_BCKGROUND = sfColor(10, 10, 0, 100);
}


final class SimulationGUI
{

	Label curCourse, curSpeed;
	TextField tgtCourseField, tgtThrottleField;

	void handleSubKinematicRes(CICSubKinematicRes res)
	{
		// course
		dmutstring cc = curCourse.content;
		mutsformat!"course: %.1f"(cc, -res.snap.rotation.compassAngle.rad2dgr);
		curCourse.content = cc;
		// speed
		cc = curSpeed.content;
		vec2d vel = cast(vec2d) res.snap.velocity;
		vec2d fwd = courseVector(res.snap.rotation);
		double proj = dot(vel, fwd);
		mutsformat!"speed: %.1f"(cc, proj);
		curSpeed.content = cc;
	}

	void updateTgtCourseDisplay(float newTgt)
	{
		tgtCourseField.content = format("%.1f", -newTgt.compassAngle.rad2dgr);
	}

	void updateTgtThrottleDisplay(float newTgt)
	{
		tgtThrottleField.content = format("%.1f", 100.0f * newTgt);
	}

	this()
	{
		Submarine playerSub = Game.simState.playerSub;

		// Tabs at the top of the screen

		Button tacticalTab = builder(new Button()).content("F1 Tactical").
			fontSize(BIG_BTN_FONT).build;
		Button passiveAcTab = builder(new Button()).content("F2 Broadband").
			fontSize(BIG_BTN_FONT).build;
		Button activeAcTab = builder(new Button()).content("F3 Active").
			fontSize(BIG_BTN_FONT).build;

		Div tabDiv = builder(hDiv([
			tacticalTab,
			passiveAcTab,
			activeAcTab
		])).fixedSize(vec2i(1, TAB_SIZE)).backgroundColor(DIV_BCKGROUND).
		backgroundVisible(true).build;

		// Course and speed labels

		curCourse = builder(new Label()).content("course: ").
			fontSize(BTN_FONT).htextAlign(HTextAlign.LEFT).build;
		curSpeed = builder(new Label()).content("speed: ").
			fontSize(BTN_FONT).htextAlign(HTextAlign.LEFT).build;

		// course and throttle setters

		Label tgtCourseLbl = builder(new Label()).content("tgt course (deg):").
			fontSize(BTN_FONT).htextAlign(HTextAlign.LEFT).build;
		Label tgtThrottleLbl = builder(new Label()).content("tgt throttle (%):").
			fontSize(BTN_FONT).htextAlign(HTextAlign.LEFT).build;

		static bool numericSymbFilter(dchar c)
		{
			if (c >= '0' && c <= '9' || c == '.' || c == '-')
				return true;
			return false;
		}

		tgtCourseField = builder(new TextField()).
			content(format("%.1f", -playerSub.targetCourse.compassAngle.rad2dgr)).
			symbolFilter(&numericSymbFilter).fontSize(BTN_FONT - 2).build;
		tgtThrottleField = builder(new TextField()).
			content(format("%.1f", 100.0f * playerSub.targetThrottle)).
			symbolFilter(&numericSymbFilter).fontSize(BTN_FONT - 2).build;

		void trySendTgtCourse()
		{
			try
			{
				float newTgt = tgtCourseField.content[0..$-1].to!float;
				if (isNaN(newTgt))
					throw new Exception("cheaky cunt, no NaNs");
				auto req = immutable CICCourseReq(-dgr2rad(newTgt));
				Game.ciccon.sendMessage(req);
			}
			catch (Exception e)
			{
				error(e.msg);
				tgtCourseField.content = "0";
			}
		}

		void trySendTgtThrottle()
		{
			try
			{
				float newTgt = tgtThrottleField.content[0..$-1].to!float;
				if (isNaN(newTgt))
					throw new Exception("cheaky cunt, no NaNs");
				if (newTgt > 100.0f)
				{
					tgtThrottleField.content = "100";
					newTgt = 100.0f;
				}
				if (newTgt < -100.0f)
				{
					tgtThrottleField.content = "-100";
					newTgt = -100.0f;
				}
				newTgt /= 100.0f;
				trace("setting throttle to: ", newTgt);
				Game.ciccon.sendMessage(immutable CICThrottleReq(newTgt));
				playerSub.targetThrottle = newTgt;
			}
			catch (Exception e)
			{
				error(e.msg);
				tgtThrottleField.content = "0";
			}
		}

		tgtCourseField.onKeyPressed += (evt)
		{
			if (evt.code == sfKeyReturn)
				trySendTgtCourse();
		};

		tgtThrottleField.onKeyPressed += (evt)
		{
			if (evt.code == sfKeyReturn)
				trySendTgtThrottle();
		};

		Game.hotkeyManager.setHotkey(Hotkey(sfKeyC), ()
		{
			tgtCourseField.requestKbFocus();
			tgtCourseField.selectAll();
		});
		Game.hotkeyManager.setHotkey(Hotkey(sfKeyT), ()
		{
			tgtThrottleField.requestKbFocus();
			tgtThrottleField.selectAll();
		});

		Div bottomDiv = builder(
			hDiv(
				[
					builder(
							vDiv([curCourse, curSpeed])
						).fixedSize(vec2i(150, 1)).build,
					builder(
							vDiv([tgtCourseLbl, tgtThrottleLbl])
						).fixedSize(vec2i(180, 1)).build,
					builder(
							vDiv([tgtCourseField, tgtThrottleField])
						).fixedSize(vec2i(65, 1)).build
				])
			).fixedSize(vec2i(1, (BTN_FONT + 6) * 2)).
			backgroundColor(DIV_BCKGROUND).backgroundVisible(true).build;

		Div topLevelDiv = builder(vDiv([
			tabDiv,
			new Waterfall(),
			bottomDiv
		])).build;

		Game.guiManager.addPanel(new Panel(topLevelDiv));
	}
}


import derelict.sfml2.graphics;
import derelict.sfml2.system;

import dsubs_client.render.camera;
import dsubs_client.core.window;


/// Zoomable waterfall display
final class Waterfall: GuiElement
{

	private
	{
		// directional resolution will be 1024 pixels, in time we save up to
		// 60 rows. Such texture weighs 5 Mb.
		enum int WIDTH = 1024;
		enum int HEIGHT = 60;
		enum float PXPERRAD = WIDTH / (PI * 2);
	}

	this()
	{
		mouseTransparent = false;
		m_renderTexture = sfRenderTexture_create(WIDTH, HEIGHT + 1, false);
		sfRenderTexture_clear(m_renderTexture, sfBlack);
		sfRenderTexture_setRepeated(m_renderTexture, sfTrue);
		m_sfRst.texture = sfRenderTexture_getTexture(m_renderTexture);
		bool ok = sfRenderTexture_setActive(m_renderTexture, false) == sfTrue;
		assert(ok);
		m_camera = new Camera2D(vec2ui(WIDTH, HEIGHT));
		m_vertPos = -HEIGHT - 1;
		m_vertices[0] = sfVertex(sfVector2f(0, 0), sfWhite, sfVector2f(0, 0));
		m_vertices[1] = sfVertex(sfVector2f(1, 0), sfWhite, sfVector2f(WIDTH - 1, 0));
		m_vertices[2] = sfVertex(sfVector2f(1, 1), sfWhite, sfVector2f(WIDTH - 1, HEIGHT - 1));
		m_vertices[3] = sfVertex(sfVector2f(0, 0), sfWhite, sfVector2f(0, 0));
		m_vertices[4] = sfVertex(sfVector2f(1, 1), sfWhite, sfVector2f(WIDTH - 1, HEIGHT - 1));
		m_vertices[5] = sfVertex(sfVector2f(0, 1), sfWhite, sfVector2f(0, HEIGHT - 1));
		foreach (ref sfVertex v; m_vertices)
			v.texCoords.y -= m_vertPos;

		// test reaction
		onMouseUp += (int x, int y, sfMouseButton btn)
			{
				import std.random;
				static int t;
				trace("debug waterfall data");
				ubyte[] data = new ubyte[181];
				foreach (ref d; data)
					d = uniform(ubyte(15), ubyte.max);
				t++;
				drawData(data, dgr2rad(t % 2 == 0 ? 180 : 90), uniform(-2.0f, 2.0f));
				completeRow();
			};
	}

	~this()
	{
		sfRenderTexture_destroy(m_renderTexture);
	}

	private
	{
		// render target to write pixel data to. 0 pixel column is just after
		// 180 course, 1023 pixel column is just before 180 course.
		sfRenderTexture* m_renderTexture;
		Camera2D m_camera;
		sfVertex[6] m_vertices;
		// m_renderTexture is perpetually streamed from
		int m_vertPos;
		sfVertex[] m_stage;

		__gshared const sfRenderStates s_states =
			sfRenderStates(sfBlendAlpha, sfTransform_Identity);
	}

	/// draw data to current row
	void drawData(ubyte[] data, float fov, float bearing)
	{
		m_stage.length = data.length * 2;
		float row = -m_vertPos - 0.5f;
		float x = WIDTH / 2.0f - PXPERRAD * (bearing + fov / 2);
		float dx = PXPERRAD * fov / data.length;
		assert(dx > 0.0f);
		if (x < 0.0f)
			x += WIDTH;
		if (x > WIDTH)
			x -= WIDTH;
		for (size_t i = 0, j = 0; i < data.length; i++, j += 2)
		{
			sfColor color = sfColor(data[i], data[i], data[i], 255);
			m_stage[j].position = sfVector2f(x, row);
			m_stage[j].color = color;
			x += dx;
			if (x > WIDTH)
			{
				// we have a special case of wraparound
				m_stage[j + 1].position = sfVector2f(WIDTH, row);
				m_stage[j + 1].color = color;
				x -= WIDTH;
				m_stage.length += 2;
				m_stage[$ - 2].position = sfVector2f(0, row);
				m_stage[$ - 2].color = color;
				m_stage[$ - 1].position = sfVector2f(x, row);
				m_stage[$ - 1].color = color;
			}
			else
			{
				m_stage[j + 1].position = sfVector2f(x, row);
				m_stage[j + 1].color = color;
			}
		}
		sfRenderTexture_setActive(m_renderTexture, sfTrue);
		sfRenderTexture_drawPrimitives(m_renderTexture, m_stage.ptr,
			m_stage.length, sfLines, &s_states);
	}

	void completeRow()
	{
		sfRenderTexture_display(m_renderTexture);
		m_vertPos++;
		if (m_vertPos > 0)
			m_vertPos -= HEIGHT;
		float row = -m_vertPos - 0.5f;
		sfVertex[2] blackLine = [sfVertex(sfVector2f(0, row), sfBlack),
			sfVertex(sfVector2f(WIDTH, row), sfBlack)];
		sfRenderTexture_drawPrimitives(m_renderTexture, blackLine.ptr,
			2, sfLines, &s_states);
		updateTexCoords();
	}

	override void updateSize()
	{
		super.updateSize();
		m_camera.screenSize = vec2ui(size.x.to!uint, size.y.to!uint);
		m_vertices[1].position.x = m_vertices[2].position.x =
			m_vertices[4].position.x = size.x;
		m_vertices[2].position.y = m_vertices[4].position.y =
			m_vertices[5].position.y = size.y;
	}

	/// update texture coordinates from camera transform
	private void updateTexCoords()
	{
		m_vertices[0].texCoords.y = m_vertices[1].texCoords.y =
			m_vertices[3].texCoords.y = -m_vertPos;
		m_vertices[2].texCoords.y = m_vertices[4].texCoords.y =
			m_vertices[5].texCoords.y = -m_vertPos + HEIGHT;
	}

	override void draw(Window wnd)
	{
		super.draw(wnd);
		sfRenderWindow_drawPrimitives(wnd.wnd, m_vertices.ptr, 6, sfTriangles,
			&m_sfRst);
	}
}