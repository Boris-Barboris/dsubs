module dsubs_client.game.states.simulation.waterfall;

import derelict.sfml2.graphics;
import derelict.sfml2.system;

import dsubs_common.math;

import dsubs_client.common;
import dsubs_client.gui;
import dsubs_client.render.camera;
import dsubs_client.core.window;
import dsubs_client.game.cic.messages;
import dsubs_client.game;


private
{
	enum int HEADER_FONT_SIZE = 16;
	enum int HEADER_SECTION_HEIGHT = 26;
	enum int VOLUME_SECTION_WIDTH = 160;
	enum sfColor DIV_BCKGROUND = sfColor(10, 10, 0, 100);
}


struct WaterfallGui
{
	Div root;
	Waterfall wf;
	Slider volumeSlider;
}


WaterfallGui createWaterfallPanel()
{
	WaterfallGui res;
	res.wf = new Waterfall();
	Slider volumeSlider = new Slider();
	volumeSlider.value = 0.5f;

	volumeSlider.onValueChanged += (float newVal)
		{
			if (newVal == 0.0f)
			{
				Game.simState.sonarSound.gain = 0.0f;
				return;
			}
			newVal = (newVal - 0.5f) * 2;
			Game.simState.sonarSound.gain = toLinear(newVal * toDb(short.max / 200));
		};

	Div volumeDiv = builder(hDiv([
		builder(new Label()).content("Volume:").fontSize(HEADER_FONT_SIZE).
			layoutType(LayoutType.CONTENT).build(),
		volumeSlider
	])).fixedSize(vec2i(VOLUME_SECTION_WIDTH, HEADER_SECTION_HEIGHT)).build;

	Div header = builder(hDiv([
		volumeDiv,
		filler()
	])).fixedSize(vec2i(0, HEADER_SECTION_HEIGHT)).build;

	res.root = builder(vDiv([
		filler(5),
		header,
		res.wf
	])).backgroundColor(DIV_BCKGROUND).build;
	res.volumeSlider = volumeSlider;

	return res;
}



/// Zoomable waterfall display
final class Waterfall: GuiElement
{

	private
	{
		// directional resolution will be 1024 pixels
		enum int WIDTH = 1024;
		enum int HEIGHT = 300;
		enum float PXPERRAD = WIDTH / (PI * 2);
		enum int COMPASS_HEADER_HEIGHT = 18;
		enum int DIRECTOR_HEADER_HEIGHT = 12;
		enum int HEADER_HEIGHT = COMPASS_HEADER_HEIGHT + DIRECTOR_HEADER_HEIGHT;
		enum int COMPASS_FONTSIZE = 14;
	}

	this()
	{
		mouseTransparent = false;
		m_renderTexture = sfRenderTexture_create(WIDTH, HEIGHT + 1, false);
		sfRenderTexture_clear(m_renderTexture, sfBlack);
		sfRenderTexture_setRepeated(m_renderTexture, sfTrue);
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
			v.position.y = HEADER_HEIGHT;
			v.texCoords.y -= m_vertPos;
		}

		// compass
		m_headerRect = sfRectangleShape_create();
		sfRectangleShape_setOutlineThickness(m_headerRect, 0.0f);
		sfRectangleShape_setFillColor(m_headerRect, sfBlack);
		sfRectangleShape_setPosition(m_headerRect, sfVector2f(0, 0));
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

		// director
		m_directorCircle = sfCircleShape_create();
		sfCircleShape_setPointCount(m_directorCircle, 3);
		sfCircleShape_setRotation(m_directorCircle, 180.0f);
		sfCircleShape_setRadius(m_directorCircle, DIRECTOR_HEADER_HEIGHT / 2);
		sfCircleShape_setFillColor(m_directorCircle, sfWhite);
		sfCircleShape_setOutlineThickness(m_directorCircle, 0.0f);
		sfFloatRect bounds = sfCircleShape_getLocalBounds(m_directorCircle);
		sfCircleShape_setOrigin(m_directorCircle,
			sfVector2f(bounds.left + bounds.width / 2, bounds.top + bounds.height / 2));

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
		sfRectangleShape_destroy(m_headerRect);
		sfCircleShape_destroy(m_directorCircle);
	}

	private
	{
		// render target to write pixel data to. 0 pixel column is just after
		// 180 course, 1023 pixel column is just before 180 course. 0 to 1023 is clockwise
		// rotation.
		sfRenderTexture* m_renderTexture;
		Camera2D m_camera;
		sfVertex[6] m_vertices;
		// m_renderTexture is perpetually streamed from
		int m_vertPos;
		long m_vertShifts;
		sfVertex[] m_stage;

		__gshared const sfRenderStates s_states =
			sfRenderStates(sfBlendAlpha, sfTransform_Identity);

		sfRectangleShape* m_headerRect; // compass background
		Label[4] m_compassLabels;
		Label m_underCursorLabel;
		bool m_cursorInside;

		// microphone director
		sfCircleShape* m_directorCircle;
		float m_listenDir = 0.0;
	}

	/// draw data to current row
	void drawData(const(ushort)[] data, float fov, float bearing, float blackLevel = 0.1f)
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
			float brightness = min(1.0f, max(0.0f, float(data[i]) / ushort.max - blackLevel));
			ubyte brt = lrint(brightness / (1 - blackLevel) * ubyte.max).to!ubyte;
			sfColor color = sfColor(brt, brt, brt, 255);
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
		m_vertShifts++;
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
		if (btn == sfMouseLeft && m_cursorInside)
		{
			updateDirectorElement(x - position.x);
			Game.ciccon.sendMessage(immutable CICListenDirReq(0, m_listenDir));
		}
	}

	private
	{
		int prev_x, prev_y;
	}

	/// Y size of waterfall display in pixels
	@property private int csizey() const
	{
		return size.y - HEADER_HEIGHT;
	}

	private void processMouseMove(int x, int y)
	{
		if (mouseFocused)
		{
			// we are panning
			m_camera.pan(vec2d(double(prev_x - x) / size.x * WIDTH,
				double(prev_y - y) / csizey * HEIGHT) / m_camera.zoom);
			constraintCamera();
			updateTexCoords();
			updateHeaderElements();
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
			float uy = HEIGHT * ((y - position.y - HEADER_HEIGHT) /
				float(csizey) - 0.5f);
			vec2d zoomPivot = 1.2f * vec2d(ux, uy);
			vec2d topan = zoomPivot / oldZoom - zoomPivot / m_camera.zoom;
			m_camera.pan(topan);
		}
		constraintCamera();
		updateTexCoords();
		updateHeaderElements();
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
			txCoord = screenWidthTx + fmod(txCoord, screenWidthTx);
		else
			txCoord = fmod(txCoord, screenWidthTx);
		return txCoord * size.x / WIDTH;
	}

	private float pixelToBearing(int px)
	{
		float tx = m_vertices[0].texCoords.x + (float(px) / size.x) *
			(m_vertices[1].texCoords.x - m_vertices[0].texCoords.x);
		return PI - tx / PXPERRAD;
	}

	private void updateHeaderElements()
	{
		// compass
		for (int i = 0; i < 4; i++)
		{
			float bearing = dgr2rad(-i * 90);
			int lblPosX = lrint(bearingToPixel(bearing)).to!int -
				m_compassLabels[i].size.x / 2;
			m_compassLabels[i].position = vec2i(position.x + lblPosX, position.y);
		}
		// director
		float dirX = bearingToPixel(m_listenDir);
		sfCircleShape_setPosition(m_directorCircle,
			sfVector2f(dirX, COMPASS_HEADER_HEIGHT + DIRECTOR_HEADER_HEIGHT / 2));
	}

	@property void listenDir(float rhs)
	{
		m_listenDir = rhs;
		float dirX = bearingToPixel(m_listenDir);
		sfCircleShape_setPosition(m_directorCircle,
			sfVector2f(dirX, COMPASS_HEADER_HEIGHT + DIRECTOR_HEADER_HEIGHT / 2));
	}

	private void updateDirectorElement(int relCursorX)
	{
		m_listenDir = pixelToBearing(relCursorX);
		sfCircleShape_setPosition(m_directorCircle,
			sfVector2f(relCursorX, COMPASS_HEADER_HEIGHT + DIRECTOR_HEADER_HEIGHT / 2));
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

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		sfRenderWindow_drawRectangleShape(wnd.wnd, m_headerRect, &m_sfRst);
		m_sfRst.texture = sfRenderTexture_getTexture(m_renderTexture);
		sfRenderWindow_drawPrimitives(wnd.wnd, m_vertices.ptr, 6, sfTriangles,
			&m_sfRst);
		m_sfRst.texture = null;
		sfRenderWindow_drawCircleShape(wnd.wnd, m_directorCircle, &m_sfRst);
		foreach (l; m_compassLabels)
			l.draw(wnd, usecsDelta);
		if (m_cursorInside)
			m_underCursorLabel.draw(wnd, usecsDelta);
	}
}
