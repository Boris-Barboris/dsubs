module dsubs_client.game.states.simulation.sonardisp;

import std.algorithm: map;

import core.time: MonoTime;

import derelict.sfml2.graphics;
import derelict.sfml2.system;

import dsubs_common.api.entities;
import dsubs_common.math.angles;
import dsubs_common.math;

import dsubs_client.common;
import dsubs_client.gui;
import dsubs_client.render.camera;
import dsubs_client.core.window;
import dsubs_client.game.cic.messages;
import dsubs_client.game.states.simulation.waterfall: PanoramicElement;
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
final class SonarDisplay: PanoramicElement!ubyte
{
	/// assumed speed of sound
	enum float SOUND_SPD = 1450.0f;

	private
	{
		/// sonar template
		SonarTemplate m_st;
		/// Index of ping currently being received
		int m_curPingId = -1;

		/// Moment of time the last ping slice was received
		MonoTime m_sliceArrivedAt;
		/// number of rows of the current slice that were already drawn.
		int m_sliceRowsDrawn;
		/// Index of ping slice currently being rendered
		int m_curSlice = -1;

		// kinematic snapshots of main submarine, required for row skew interpolation
		KinematicSnapshot m_pingStartSnap;	/// snapshot of a submarine when ping has started
		KinematicSnapshot[3] m_kinetSnaps;	/// 3 last snapshots of a submarine
		/// index of the start snapshot of the currently-rendered slice
		int m_curSliceSnapIdx = 3;

		/// contents of the slice being drawn
		const(ubyte)[] m_hostImage;
	}

	this(const SonarTemplate st)
	{
		m_st = st;
		m_pyperworldy = st.radResol / SOUND_SPD;
		m_sliceRowsDrawn = st.radResol;		// initial position of slice is fully drawn

		PanoramicParams params;
		params.height = st.maxDuration * st.radResol;
		params.camViewPortWidth = to!int(params.width * st.fov / (2 * PI));
		params.camViewPortHeight = params.height;
		super(params);
	}

	/// we require sonar rotation interpolation in order to correcly skew slice rows.
	void handleSubKinematicRes(CICSubKinematicRes res)
	{
		m_kinetSnaps[0] = m_kinetSnaps[1];
		m_kinetSnaps[1] = m_kinetSnaps[2];
		m_kinetSnaps[2] = res.snap;
		m_curSliceSnapIdx = max(0, m_curSliceSnapIdx - 1);
	}

	/// memorize new slice of sonar data
	void putSliceData(const SonarSliceData data)
	{
		assert(data.sonarIdx == 0);
		assert(m_curPingId < data.pingId ||
			(data.sliceId > m_curSlice && m_curPingId == data.pingId));
		assert(data.sliceId < m_st.maxDuration);
		if (m_curPingId < data.pingId)
		{
			// completely new ping has arrived
			m_curPingId = data.pingId;
			m_pingStartSnap = m_kinetSnaps[1];
		}
		finishCurSlice();
		m_curSliceSnapIdx++;
		m_curSlice = data.sliceId;
		m_sliceArrivedAt = MonoTime.currTime;
		m_sliceRowsDrawn = 0;
		// update hostImage from new data
		m_hostImage = data.data;
	}

	private float interpolateRotation(int idx0, int rowInSlice)
	{
		float t = (rowInSlice + 0.5f) / m_st.radResol;
		return m_st.mount.rotation +
			chspline(m_kinetSnaps[idx0].rotation, m_kinetSnaps[idx0 + 1].rotation,
				m_kinetSnaps[idx0].angVel, m_kinetSnaps[idx0 + 1].angVel, t, 1.0f);
	}

	/// flush yet undrawn rows of old slice to the texture
	private void finishCurSlice()
	{
		ensureRowNumberDrawn(m_st.radResol);
	}

	private void ensureRowNumberDrawn(int rowCount)
	{
		assert(rowCount <= m_st.radResol && rowCount >= 0);
		if (m_sliceRowsDrawn >= rowCount)
			return;
		// we draw rows one-by-one
		for (int row = m_sliceRowsDrawn; row < rowCount; row++)
		{
			float bearing = interpolateRotation(m_curSliceSnapIdx, row);
			float rowY = m_curSlice * m_st.radResol + row + 0.5f;
			clearRow(rowY);
			int hostIdx = (m_st.radResol - row - 1) * m_st.resol;
			drawRow(m_hostImage[hostIdx .. hostIdx + m_st.resol], rowY, m_st.fov, bearing);
		}
		m_sliceRowsDrawn = rowCount;
	}

	/// draw new rows of the slice, based on timing
	private void drawCurSlice()
	{
		if (m_sliceRowsDrawn >= m_st.radResol)
			return;
		auto timeSinceStart = MonoTime.currTime - m_sliceArrivedAt;
		int mustHaveDrawnRows = to!int(m_st.radResol * timeSinceStart.total!"msecs" / 1000.0f);
		mustHaveDrawnRows = min(mustHaveDrawnRows, m_st.radResol);
		ensureRowNumberDrawn(mustHaveDrawnRows);
	}

	private float pixelToRange(int px)
	{
		if (contentHeight <= 0)
			return 0.0f;
		float ty = m_vertices[1].texCoords.y + (float(px) / contentHeight) *
			(m_vertices[2].texCoords.y - m_vertices[1].texCoords.y);
		return (m_height - ty) / m_pyperworldy;
	}

	private float rangeToPixel(float range)
	{
		float camCoord = m_camera.transform2screen(vec2d(0, range)).y;
		return camCoord * size.y / m_height;
	}

	override void updateCursorLabel(int relCursorX, int relCursorY)
	{
		import std.format;

		float worldBearing = clampAnglePi(pixelToBearing(relCursorX));
		float range = pixelToRange(relCursorY);
		int lblPosX = lrint(bearingToPixel(worldBearing)).to!int -
				m_underCursorLabel.size.x / 2;
		m_underCursorLabel.position = vec2i(position.x + lblPosX, position.y);
		dmutstring labelContent = m_underCursorLabel.content;
		auto rw = mutstringRewriter(labelContent);
		formattedWrite!"%d, %dm"(rw, -worldBearing.compassAngle.rad2dgr.to!int, range.to!int);
		m_underCursorLabel.content = rw.get();
	}

	override void draw(Window wnd, long usecsDelta)
	{
		drawCurSlice();
		super.draw(wnd, usecsDelta);
	}
}