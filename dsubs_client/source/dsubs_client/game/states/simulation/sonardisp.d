module dsubs_client.game.states.simulation.sonardisp;

import core.time: MonoTime;

import derelict.sfml2.graphics;
import derelict.sfml2.system;

import dsubs_common.api.entities;
import dsubs_common.math.angles;

import dsubs_client.common;
import dsubs_client.gui;
import dsubs_client.render.camera;
import dsubs_client.core.window;
import dsubs_client.game.cic.messages;
import dsubs_client.game;


private
{
	enum int HEADER_FONT_SIZE = 16;
	enum int HEADER_SECTION_HEIGHT = 32;
	enum int PING_BUTTON_HEIGHT = 30;
	enum int PING_BUTTON_WIDTH = 100;
	enum sfColor PING_BUTTON_BCKGROUND = sfColor(200, 50, 50, 255);
	enum int POWER_SECTION_WIDTH = 160;
	enum sfColor DIV_BCKGROUND = sfColor(10, 10, 0, 100);
}


struct SonarGui
{
	Div root;
	SonarDisplay sonar;
	Button pingBtn;
	Slider powerSlider;
}


SonarGui createSonarGui(const SonarTemplate st)
{
	SonarGui res;
	res.sonar = new SonarDisplay(st);
	res.powerSlider = new Slider();
	res.powerSlider.value = 1.0f;

	res.pingBtn = builder(new Button()).content("Ping").
		fontSize(PING_BUTTON_HEIGHT - 4).fixedSize(
			vec2i(PING_BUTTON_WIDTH, PING_BUTTON_HEIGHT)).
			backgroundColor(PING_BUTTON_BCKGROUND).build();

	res.pingBtn.onClick += ()
		{
			// request ping
			float pingMag = st.minPingIlevel +
				res.powerSlider.value * (st.maxPingIlevel - st.minPingIlevel);
			Game.ciccon.sendMessage(immutable CICEmitPingReq(0, pingMag));
		};

	Div powerDiv = builder(hDiv([
		builder(new Label()).content("power:").fontSize(HEADER_FONT_SIZE).
			layoutType(LayoutType.CONTENT).build,
		res.powerSlider
	])).fixedSize(vec2i(POWER_SECTION_WIDTH, HEADER_SECTION_HEIGHT)).build;

	Div header = builder(hDiv([
		res.pingBtn,
		filler(10),
		powerDiv,
		filler()
	])).fixedSize(vec2i(0, HEADER_SECTION_HEIGHT)).build;

	res.root = builder(vDiv([
		filler(5),
		header,
		res.sonar
	])).backgroundColor(DIV_BCKGROUND).build;

	return res;
}


/// Zoomable active sonar display, similar to waterfall, but flows bottom to top.
final class SonarDisplay: GuiElement
{

	private
	{
		/// if there are 100 beams in sonar image slice, we'll render the slices into
		/// a texture with a width of 100 * WIDTH_MULTIPLIER.
		enum int WIDTH_MULTIPLIER = 5;
		enum int COMPASS_HEADER_HEIGHT = 18;
		enum int HEADER_HEIGHT = COMPASS_HEADER_HEIGHT;
		enum int COMPASS_FONTSIZE = 14;
	}

	this(const SonarTemplate st)
	{
		mouseTransparent = false;
		m_st = st;
		m_width = st.resol * WIDTH_MULTIPLIER;
		m_height = st.radResol * st.maxDuration;
		m_pxperrad = m_width / (PI * 2);
		m_pxpermeter = st.radResol / (SOUND_SPD / 2);
		m_hostImage.length = st.radResol * m_width;
		m_sliceRowsDrawn = st.radResol;

		// create texture
		m_texture = sfTexture_create(m_width, m_height);
		sfTexture_setRepeated(m_texture, sfTrue);
		clear();
		// camera is used to generate texture coordinates for m_vertices
		m_camera = new Camera2D(vec2ui(to!uint(m_pxperrad * st.fov), m_height), false);
		m_camera.pan(vec2d(m_width * 0.5, m_height * 0.5));

		// m_vertices form a rectanglular area to draw pixel data to
		m_vertices[0] = sfVertex(sfVector2f(0, HEADER_HEIGHT), sfWhite, sfVector2f(0, 0));
		m_vertices[1] = sfVertex(sfVector2f(1, HEADER_HEIGHT), sfWhite, sfVector2f(m_width - 1, 0));
		m_vertices[2] = sfVertex(sfVector2f(1, HEADER_HEIGHT + 1), sfWhite, sfVector2f(m_width - 1, m_height - 1));
		m_vertices[3] = sfVertex(sfVector2f(0, HEADER_HEIGHT), sfWhite, sfVector2f(0, 0));
		m_vertices[4] = sfVertex(sfVector2f(1, HEADER_HEIGHT + 1), sfWhite, sfVector2f(m_width - 1, m_height - 1));
		m_vertices[5] = sfVertex(sfVector2f(0, HEADER_HEIGHT + 1), sfWhite, sfVector2f(0, m_height - 1));
		updateTexCoords();

		// compass
		m_headerRect = sfRectangleShape_create();
		sfRectangleShape_setOutlineThickness(m_headerRect, 0.0f);
		sfRectangleShape_setFillColor(m_headerRect, sfBlack);
		sfRectangleShape_setPosition(m_headerRect, sfVector2f(0, 0));
		m_underCursorLabel = builder(new Label()).fontSize(COMPASS_FONTSIZE).
			size(vec2i(80, COMPASS_HEADER_HEIGHT)).fontColor(sfYellow).
			htextAlign(HTextAlign.CENTER).build();

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
		sfTexture_destroy(m_texture);
		sfRectangleShape_destroy(m_headerRect);
	}

	private
	{
		// render target to write pixel data to. 0 pixel column is just after (right)
		// 180 course, last pixel column is just before 180 course (left of it).
		// 0 to last is clockwise rotation.
		sfTexture* m_texture;
		Camera2D m_camera;
		sfVertex[6] m_vertices;
		int m_width;
		int m_height;
		float m_pxperrad;
		float m_pxpermeter;
		SonarTemplate m_st;
		sfRectangleShape* m_headerRect; // compass background
		Label m_underCursorLabel;
		bool m_cursorInside;
		// currently rendered ping
		int m_curPingId = -1;
		// ram buffer
		sfUint8[4][] m_hostImage;

		// stuff for smooth additive rendering each frame
		MonoTime m_sliceArrivedAt;
		int m_sliceRowsDrawn;
		int m_curSlice = -1;
	}

	/// memorize new slice of sonar data
	void putSliceData(const SonarSliceData data)
	{
		assert(data.sonarIdx == 0);
		assert(m_curPingId <= data.pingId);
		if (m_curPingId < data.pingId)
		{
			// clear();
			m_curPingId = data.pingId;
		}
		finishCurSlice();
		m_curSlice = data.sliceId;
		m_sliceArrivedAt = MonoTime.currTime;
		m_sliceRowsDrawn = 0;
		// blit data to hostImage
		for (size_t i = 0; i < data.data.length; i++)
		{
			sfUint8[4] color;
			// black and white
			color[0] = color[1] = color[2] = data.data[i];
			color[3] = 255;
			m_hostImage[i] = color;
		}
	}

	/// flush yet undrawn rows of old slice to the texture
	private void finishCurSlice()
	{
		if (m_sliceRowsDrawn >= m_st.radResol)
			return;
		int leftRows = m_st.radResol - m_sliceRowsDrawn;
		sfTexture_updateFromPixels(m_texture,
			cast(ubyte*) m_hostImage.ptr,
			m_width, leftRows,
			0, m_height - (m_curSlice + 1) * m_st.radResol);
		m_sliceRowsDrawn = m_st.radResol;
	}

	/// draw new rows of the slice, based on timing
	private void drawCurSlice()
	{
		if (m_sliceRowsDrawn >= m_st.radResol)
			return;
		auto timeSinceStart = MonoTime.currTime - m_sliceArrivedAt;
		int mustHaveDrawnRows = to!int(m_st.radResol * timeSinceStart.total!"msecs" / 1000);
		mustHaveDrawnRows = min(mustHaveDrawnRows, m_st.radResol);
		if (mustHaveDrawnRows <= m_sliceRowsDrawn)
			return;
		int mustNotDrawn = m_st.radResol - mustHaveDrawnRows;
		int toDrawNow = mustHaveDrawnRows - m_sliceRowsDrawn;
		// push hostImage to GPU
		sfTexture_updateFromPixels(m_texture,
			cast(ubyte*) &m_hostImage[mustNotDrawn * m_width],
			m_width, toDrawNow,
			0, m_height - (m_curSlice + 1) * m_st.radResol + mustNotDrawn);
		m_sliceRowsDrawn = mustHaveDrawnRows;
	}

	private void clear()
	{
		for (size_t i = 0; i < m_hostImage.length; i++)
		{
			sfUint8[4] color;
			color[3] = 255;
			m_hostImage[i] = color;
		}
		for (int j = 0; j < m_st.maxDuration; j++)
		{
			sfTexture_updateFromPixels(m_texture, cast(ubyte*) m_hostImage.ptr,
				m_width, m_st.radResol,
				0, m_height - (j + 1) * m_st.radResol);
		}
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

	/// Y size of sonar display in pixels
	@property private int csizey() const
	{
		return size.y - HEADER_HEIGHT;
	}

	private void onCameraChange()
	{
		constraintCamera();
		updateTexCoords();
		updateHeaderElements();
	}

	private void processMouseMove(int x, int y)
	{
		if (mouseFocused)
		{
			// we are panning
			m_camera.pan(vec2d(double(prev_x - x) / size.x * m_width,
				double(prev_y - y) / csizey * m_height) / m_camera.zoom);
			onCameraChange();
			prev_x = x;
			prev_y = y;
		}
		updateCursorLabel(x - position.x, y - position.y - HEADER_HEIGHT);
	}

	private enum float ZOOM_SPD = 0.14f;

	private void processMouseScroll(int x, int y, float delta)
	{
		double oldZoom = m_camera.zoom;
		m_camera.zoom = max(1.0, min(16.0, m_camera.zoom * (1 + ZOOM_SPD * delta)));
		if (delta > 0)
		{
			float ux = m_width * ((x - position.x) / float(size.x) - 0.5f);
			float uy = m_height * ((y - position.y - HEADER_HEIGHT) /
				float(csizey) - 0.5f);
			vec2d zoomPivot = 1.2f * vec2d(ux, uy);
			vec2d topan = zoomPivot / oldZoom - zoomPivot / m_camera.zoom;
			m_camera.pan(topan);
		}
		onCameraChange();
	}

	private void constraintCamera()
	{
		double overtop = -m_camera.transform2world(vec2d(0, 0)).y;
		if (overtop > 0.0)
			m_camera.pan(vec2d(0, overtop));
		double underbot = m_camera.transform2world(vec2d(0, m_height)).y - m_height;
		if (underbot > 0.0)
			m_camera.pan(vec2d(0, -underbot));
		double overleft = -m_camera.transform2world(vec2d(0, 0)).x;
		if (overleft > 0.0)
			m_camera.pan(vec2d(overleft, 0));
		double overright = m_camera.transform2world(vec2d(m_width, 0)).x - m_width;
		if (overright > 0.0)
			m_camera.pan(vec2d(-overright, 0));
	}

	override void updatePosition()
	{
		super.updatePosition();
		updateHeaderElements();
	}

	override void updateSize()
	{
		super.updateSize();
		sfRectangleShape_setSize(m_headerRect, sfVector2f(size.x, HEADER_HEIGHT));
		m_vertices[1].position.x = m_vertices[2].position.x =
			m_vertices[4].position.x = size.x;
		m_vertices[2].position.y = m_vertices[4].position.y =
			m_vertices[5].position.y = size.y;
		updateHeaderElements();
	}

	/// update texture coordinates from camera transform
	private void updateTexCoords()
	{
		vec2d ul = m_camera.transform2world(vec2d(0.0, 0.0));
		vec2d br = m_camera.transform2world(vec2d(m_width, m_height));
		// x
		m_vertices[0].texCoords.x = m_vertices[3].texCoords.x =
			m_vertices[5].texCoords.x = ul.x;
		m_vertices[1].texCoords.x = m_vertices[2].texCoords.x =
			m_vertices[4].texCoords.x = br.x;
		// y
		m_vertices[0].texCoords.y = m_vertices[1].texCoords.y =
			m_vertices[3].texCoords.y = ul.y;
		m_vertices[2].texCoords.y = m_vertices[4].texCoords.y =
			m_vertices[5].texCoords.y = br.y;
	}

	// bearing to pixel in screen space
	private float bearingToPixel(float bearing)
	{
		float txCoord = m_camera.transform2screen(
			vec2d(m_width / 2.0f - m_pxperrad * bearing, 0)).x;
		float screenWidthTx = m_width * m_camera.zoom;
		if (txCoord < 0.0f)
			txCoord = screenWidthTx + fmod(txCoord, screenWidthTx);
		else
			txCoord = fmod(txCoord, screenWidthTx);
		return txCoord * size.x / m_width;
	}

	private float pixelToBearing(int px)
	{
		float tx = m_vertices[0].texCoords.x + (float(px) / size.x) *
			(m_vertices[1].texCoords.x - m_vertices[0].texCoords.x);
		return 0.5f * m_st.fov - tx / m_pxperrad;
	}

	enum float SOUND_SPD = 1450.0f;

	private float pixelToRange(int px)
	{
		if (csizey <= 0)
			return 0.0f;
		float tx = m_vertices[0].texCoords.y + (float(px) / csizey) *
			(m_vertices[2].texCoords.y - m_vertices[0].texCoords.y);
		return SOUND_SPD * m_st.maxDuration * 0.5f - tx / m_pxpermeter;
	}

	private float rangeToPixel(float range)
	{
		float txCoord = m_camera.transform2screen(vec2d(0, range)).y;
		return txCoord * size.y / m_height;
	}

	private void updateHeaderElements()
	{
	}

	private void updateCursorLabel(int relCursorX, int relCursorY)
	{
		import std.format;

		float relBearing = clampAnglePi(pixelToBearing(relCursorX));
		float worldRot = Game.simState.playerSub.transform.wrotation;
		float worldBearing = compassAngle(worldRot + relBearing);
		float range = pixelToRange(relCursorY);
		int lblPosX = lrint(bearingToPixel(relBearing)).to!int -
				m_underCursorLabel.size.x / 2;
		m_underCursorLabel.position = vec2i(position.x + lblPosX, position.y);
		dmutstring labelContent = m_underCursorLabel.content;
		auto rw = mutstringRewriter(labelContent);
		formattedWrite!"%d, %dm"(rw, -worldBearing.rad2dgr.to!int, range.to!int);
		m_underCursorLabel.content = rw.get();
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		sfRenderWindow_drawRectangleShape(wnd.wnd, m_headerRect, &m_sfRst);
		drawCurSlice();
		m_sfRst.texture = m_texture;
		sfRenderWindow_drawPrimitives(wnd.wnd, m_vertices.ptr, 6, sfTriangles,
			&m_sfRst);
		m_sfRst.texture = null;
		if (m_cursorInside)
			m_underCursorLabel.draw(wnd, usecsDelta);
	}

	/// Sonar display has it's own overlay, wich is drawing contacts on top of sonar
	/// data.
	final class SonarDispOverlay: Overlay
	{
		protected vec2d world2screenPos(vec2d world)
		{
			return vec2d(
				outer.bearingToPixel(world.x),
				outer.rangeToPixel(world.y));
		}
	}
}