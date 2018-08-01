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
	enum sfColor DIV_BCKGROUND = sfColor(10, 10, 0, 100);
}


final class SimulationGUI
{

	private
	{
		Label curCourse, curSpeed;
		TextField tgtCourseField, tgtThrottleField;
		Waterfall m_sonarGui;
	}

	@property Waterfall sonarGui() { return m_sonarGui; }

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
		Button psonarTab = builder(new Button()).content("F2 Passive sonar").
			fontSize(BIG_BTN_FONT).build;
		Button asonarTab = builder(new Button()).content("F3 Active sonar").
			fontSize(BIG_BTN_FONT).build;

		Game.hotkeyManager.setHotkey(Hotkey(sfKeyF1), ()
		{
			tacticalTab.simulateClick();
		});
		Game.hotkeyManager.setHotkey(Hotkey(sfKeyF2), ()
		{
			psonarTab.simulateClick();
		});
		Game.hotkeyManager.setHotkey(Hotkey(sfKeyF3), ()
		{
			asonarTab.simulateClick();
		});

		Div tabDiv = builder(hDiv([
			tacticalTab,
			psonarTab,
			asonarTab
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

		GuiElement tabFiller = filler();
		m_sonarGui = new Waterfall();

		Div topLevelDiv = builder(vDiv([
			tabDiv,
			tabFiller,
			bottomDiv
		])).build;

		void setMiddlePane(GuiElement el)
		{
			topLevelDiv.setChild(el, 1);
		}

		tacticalTab.onClick += (btn) { setMiddlePane(tabFiller); };
		psonarTab.onClick += (btn) { setMiddlePane(m_sonarGui); };
		asonarTab.onClick += (btn) { setMiddlePane(tabFiller); };

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
		// 120 rows. Such texture weighs 5 Mb.
		enum int WIDTH = 1024;
		enum int HEIGHT = 120;
		enum float PXPERRAD = WIDTH / (PI * 2);
		enum int COMPASS_HEADER_HEIGHT = 18;
		enum int COMPASS_FONTSIZE = 14;
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
		// camera is used to generate texture coordinates for m_vertices
		m_camera = new Camera2D(vec2ui(WIDTH, HEIGHT), false);
		m_camera.pan(vec2d(WIDTH * 0.5, HEIGHT * 0.5));
		m_vertPos = -HEIGHT - 1;
		// m_vertices form a rectanglular area to draw broadband data to
		m_vertices[0] = sfVertex(sfVector2f(0, 0), sfWhite, sfVector2f(0, 0));
		m_vertices[1] = sfVertex(sfVector2f(1, 0), sfWhite, sfVector2f(WIDTH - 1, 0));
		m_vertices[2] = sfVertex(sfVector2f(1, 1), sfWhite, sfVector2f(WIDTH - 1, HEIGHT - 1));
		m_vertices[3] = sfVertex(sfVector2f(0, 0), sfWhite, sfVector2f(0, 0));
		m_vertices[4] = sfVertex(sfVector2f(1, 1), sfWhite, sfVector2f(WIDTH - 1, HEIGHT - 1));
		m_vertices[5] = sfVertex(sfVector2f(0, 1), sfWhite, sfVector2f(0, HEIGHT - 1));
		foreach (ref sfVertex v; m_vertices)
		{
			v.position.y = COMPASS_HEADER_HEIGHT;
			v.texCoords.y -= m_vertPos;
		}

		// compass
		m_compassRect = sfRectangleShape_create();
		sfRectangleShape_setOutlineThickness(m_compassRect, 0.0f);
		sfRectangleShape_setFillColor(m_compassRect, sfBlack);
		sfRectangleShape_setPosition(m_compassRect, sfVector2f(0, 0));
		for (int i = 0; i < 4; i++)
		{
			Label lbl = new Label();
			lbl.fontSize = COMPASS_FONTSIZE;
			lbl.size = vec2i(40, COMPASS_HEADER_HEIGHT);
			lbl.fontColor = sfWhite;
			lbl.htextAlign = HTextAlign.CENTER;
			lbl.content = (i * 90).to!string;
			m_compassLabels[i] = lbl;
		}
		m_underCursorLabel = builder(new Label()).fontSize(COMPASS_FONTSIZE).
			size(vec2i(40, COMPASS_HEADER_HEIGHT)).fontColor(sfYellow).
			htextAlign(HTextAlign.CENTER).build();

		// test handlers
		// onMouseUp += (int x, int y, sfMouseButton btn)
		// 	{
		// 		if (btn != sfMouseLeft)
		// 			return;
		// 		import std.random;
		// 		static int t;
		// 		trace("debug waterfall data");
		// 		ubyte[] data = new ubyte[WIDTH / 2];
		// 		foreach (ref d; data)
		// 			d = uniform(ubyte(60), ubyte.max);
		// 		t++;
		// 		drawData(data, dgr2rad(90), dgr2rad(90 - 5 * t));
		// 		completeRow();
		// 	};

		// mouse and keyboard handlers
		onMouseDown += &processMouseDown;
		onMouseUp += &processMouseUp;
		onMouseMove += &processMouseMove;
		onMouseScroll += &processMouseScroll;
		onMouseEnter += () { m_cursorInside = true; };
		onMouseLeave += () { m_cursorInside = false; };
	}

	~this()
	{
		sfRenderTexture_destroy(m_renderTexture);
		sfRectangleShape_destroy(m_compassRect);
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

		sfRectangleShape* m_compassRect; // compass background
		Label[4] m_compassLabels;
		Label m_underCursorLabel;
		bool m_cursorInside;
	}

	/// draw data to current row
	void drawData(ubyte[] data, float fov, float bearing)
	{
		m_stage.length = data.length * 2;
		float row = m_vertPos < 0 ? -m_vertPos - 0.5f : HEIGHT + 0.5f;
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
			m_vertPos -= HEIGHT + 1;
		float row = m_vertPos < 0 ? -m_vertPos - 0.5f : HEIGHT + 0.5f;
		sfVertex[2] blackLine = [sfVertex(sfVector2f(0, row), sfBlack),
			sfVertex(sfVector2f(WIDTH, row), sfBlack)];
		sfRenderTexture_drawPrimitives(m_renderTexture, blackLine.ptr,
			2, sfLines, &s_states);
		updateTexCoords();
	}

	private void processMouseDown(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseRight)
		{
			requestMouseFocus();
			prev_x = x;
			prev_y = y;
		}
	}

	private void processMouseUp(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseRight)
			returnMouseFocus();
	}

	private
	{
		int prev_x, prev_y;
	}

	/// Y size of waterfall display in pixels
	@property private int csizey() const
	{
		return size.y - COMPASS_HEADER_HEIGHT;
	}

	private void processMouseMove(int x, int y)
	{
		if (m_mouseFocused)
		{
			// we are panning
			m_camera.pan(vec2d(double(prev_x - x) / size.x * WIDTH,
				double(prev_y - y) / csizey * HEIGHT) / m_camera.zoom);
			constraintCamera();
			updateTexCoords();
			updateCompassLabels();
			prev_x = x;
			prev_y = y;
		}
		updateCursorLabel(x - position.x);
	}

	private enum float ZOOM_SPD = 0.14f;

	private void processMouseScroll(int x, int y, float delta)
	{
		double oldZoom = m_camera.zoom;
		m_camera.zoom = max(1.0, min(16.0, m_camera.zoom * (1 + ZOOM_SPD * delta)));
		if (delta > 0)
		{
			float ux = WIDTH * ((x - position.x) / float(size.x) - 0.5f);
			float uy = HEIGHT * ((y - position.y - COMPASS_HEADER_HEIGHT) /
				float(csizey) - 0.5f);
			vec2d zoomPivot = 1.2f * vec2d(ux, uy);
			vec2d topan = zoomPivot / oldZoom - zoomPivot / m_camera.zoom;
			m_camera.pan(topan);
		}
		constraintCamera();
		updateTexCoords();
		updateCompassLabels();
	}

	private void constraintCamera()
	{
		double overtop = -m_camera.transform2world(vec2d(0, 0)).y;
		if (overtop > 0.0)
			m_camera.pan(vec2d(0, overtop));
		double underbot = m_camera.transform2world(vec2d(0, HEIGHT)).y - HEIGHT;
		if (underbot > 0.0)
			m_camera.pan(vec2d(0, -underbot));
	}

	override void updatePosition()
	{
		super.updatePosition();
		updateCompassLabels();
	}

	override void updateSize()
	{
		super.updateSize();
		sfRectangleShape_setSize(m_compassRect, sfVector2f(size.x, COMPASS_HEADER_HEIGHT));
		m_vertices[1].position.x = m_vertices[2].position.x =
			m_vertices[4].position.x = size.x;
		m_vertices[2].position.y = m_vertices[4].position.y =
			m_vertices[5].position.y = size.y;
		updateCompassLabels();
	}

	/// update texture coordinates from camera transform
	private void updateTexCoords()
	{
		// x
		m_vertices[0].texCoords.x = m_vertices[3].texCoords.x =
			m_vertices[5].texCoords.x = m_camera.transform2world(vec2d(0.0, 0.0)).x;
		m_vertices[1].texCoords.x = m_vertices[2].texCoords.x =
			m_vertices[4].texCoords.x = m_camera.transform2world(vec2d(WIDTH, 0.0)).x;
		// y
		m_vertices[0].texCoords.y = m_vertices[1].texCoords.y =
			m_vertices[3].texCoords.y = m_camera.transform2world(vec2d(0.0, 0.0f)).y - m_vertPos;
		m_vertices[2].texCoords.y = m_vertices[4].texCoords.y =
			m_vertices[5].texCoords.y = m_camera.transform2world(vec2d(0.0, HEIGHT)).y - m_vertPos;
	}

	// bearing to pixel in screen space
	private float bearingToPixel(float bearing)
	{
		float txCoord = m_camera.transform2screen(
			vec2d(WIDTH / 2.0f - PXPERRAD * bearing, 0)).x;
		float screenWidthTx = WIDTH * m_camera.zoom;
		if (txCoord < 0.0f)
			txCoord = screenWidthTx + txCoord % screenWidthTx;
		else
			txCoord = txCoord % screenWidthTx;
		return txCoord * size.x / WIDTH;
	}

	private float pixelToBearing(int px)
	{
		float tx = m_vertices[0].texCoords.x + (float(px) / size.x) *
			(m_vertices[1].texCoords.x - m_vertices[0].texCoords.x);
		return PI - tx / PXPERRAD;
	}

	private void updateCompassLabels()
	{
		for (int i = 0; i < 4; i++)
		{
			float bearing = dgr2rad(-i * 90);
			int lblPosX = lrint(bearingToPixel(bearing)).to!int -
				m_compassLabels[i].size.x / 2;
			m_compassLabels[i].position = vec2i(position.x + lblPosX, position.y);
		}
	}

	private void updateCursorLabel(int relCoursorX)
	{
		import std.format;

		float bearing = clampAnglePi(pixelToBearing(relCoursorX));
		int lblPosX = lrint(bearingToPixel(bearing)).to!int -
				m_underCursorLabel.size.x / 2;
		m_underCursorLabel.position = vec2i(position.x + lblPosX, position.y);
		dmutstring labelContent = m_underCursorLabel.content;
		int bearingInt = lrint(-compassAngle(bearing).rad2dgr).to!int;
		auto rw = mutstringRewriter(labelContent);
		formattedWrite!"%d"(rw, bearingInt);
		m_underCursorLabel.content = rw.get();
	}

	override void draw(Window wnd)
	{
		super.draw(wnd);
		sfRenderWindow_drawRectangleShape(wnd.wnd, m_compassRect, &m_sfRst);
		sfRenderWindow_drawPrimitives(wnd.wnd, m_vertices.ptr, 6, sfTriangles,
			&m_sfRst);
		foreach (l; m_compassLabels)
			l.draw(wnd);
		if (m_cursorInside)
			m_underCursorLabel.draw(wnd);
	}
}