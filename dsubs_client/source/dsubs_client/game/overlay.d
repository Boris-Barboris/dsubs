module dsubs_client.game.overlay;

import std.conv: to;
import std.math;
import std.experimental.logger;

import derelict.sfml2.graphics;

import dsubs_common.math;

import dsubs_client.common;
import dsubs_client.core.window;
import dsubs_client.render.shapes;
import dsubs_client.render.worldmanager;
import dsubs_client.math.transform;
import dsubs_client.gui;
import dsubs_client.game;
import dsubs_client.game.sonardisp;
import dsubs_client.game.cic.messages;
import dsubs_client.game.entities;
import dsubs_client.game.cameracontroller;
import dsubs_client.game.kinetic;
import dsubs_client.game.contacts;


/// Cache of pre-constructed shapes for overlay rendering
final class ContactOverlayShapeCahe
{
	this()
	{
		m_shapes[ContactType.unknown] =
			new CircleShape(8.0f, 4, sfColor(244, 241, 66, 255), 2);
		m_shapes[ContactType.environment] =
			new CircleShape(7.0f, 6, sfColor(107, 244, 65, 255), 2);
		m_shapes[ContactType.submarine] =
			new CircleShape(8.0f, 12, sfColor(255, 132, 10, 255), 2);
		m_shapes[ContactType.weapon] =
			new CircleShape(5.0f, 3, sfRed, 2);
		m_shapes[ContactType.decoy] =
			new CircleShape(5.0f, 5, sfColor(152, 9, 255, 255), 2);
		m_onHoverRect = new RectangleShape(vec2f(22.0f, 22.0f), sfWhite);
		m_onHoverRect.position = -vec2f(1, 1);
		m_posDataMainShape = new RectangleShape(vec2f(5, 5)), sfRed);
		m_posDataMainShape = -vec2f(1, 1);
		m_posDataOnHoverRect = new RectangleShape(vec2f(8.0f, 8.0f), sfWhite);
		m_posDataOnHoverRect.position = -vec2f(1, 1);
	}

	private
	{
		CircleShape[ContactType.max + 1] m_shapes;
		RectangleShape m_onHoverRect;
		RectangleShape m_posDataMainShape;
		RectangleShape m_posDataOnHoverRect;
	}

	CircleShape forContactType(ContactType t)
	{
		return m_shapes[t];
	}

	@property RectangleShape onHoverRect()
	{
		return m_onHoverRect;
	}

	@property RectangleShape posDataMainShape()
	{
		return m_posDataMainShape;
	}

	@property RectangleShape posDataOnHoverRect()
	{
		return m_posDataOnHoverRect;
	}
}


pragma(inline)
private ContactOverlayShapeCahe ctcOverlayCache()
{
	return Game.simState.contactOverlayShapeCache;
}

private __gshared vec2i s_dragOffset;



class OverlayElementWithHover: OverlayElement
{
	this(Overlay owner)
	{
		super(owner);
		onMouseEnter += (o) { m_hovered = true; };
		onMouseLeave += (o) { m_hovered = false; };
	}

	protected
	{
		RectangleShape m_onHoverRect;
		bool m_hovered;
	}
}


class ContactDataOverlayElement: OverlayElementWithHover
{
	this(Overlay owner, ClientContactData* data)
	{
		super(owner);
		m_data = data;
	}

	mixin Readonly!(ClientContactData*, "data");

	/// When the contact data updates from CIC message, this method is called;
	abstract void updateFromData();
}


final class SonarDispContactDataElement: ContactDataOverlayElement
{
	this(SonarDisplay.SonarOverlay owner, ClientContactData* data, ClientContact contact)
	{
		assert(data.type == DataType.Position);
		assert(data.source.type == DataSourceType.ActiveSonar);
		super(owner, data);
		m_onHoverRect = ctcOverlayCache.onHoverRect;
		// we need to calculate bearing and range relative to last ping source
		// in order to be able to draw it
		if (owner.outer.havePingSourcePosition)
			processNewPing(owner.outer.pingSourcePosition);
		updateFromContact(contact);

		onMouseDown += &processMouseDown;
		onMouseMove += &processMouseMove;
		onMouseUp += &processMouseUp;
	}

	private @property SonarDisplay.SonarOverlay owner()
	{
		return cast(SonarDisplay.SonarOverlay) super.owner;
	}

	override void updateFromData()
	{
		if (owner.outer.havePingSourcePosition)
			processNewPing(owner.outer.pingSourcePosition);
	}

	void updateFromContact(ClientContact contact)
	{
		m_mainShape = ctcOverlayCache.forContactType(contact.type);
		size = cast(vec2i) vec2f(2 * m_mainShape.radius + 4, 2 * m_mainShape.radius + 4);
		if (m_contactName is null)
		{
			m_contactName = new Label();
			m_contactName.fontSize = 15;
			m_contactName.content = contact.id.to!string;
			m_contactName.size = cast(vec2i) vec2f(m_contactName.contentWidth + 10,
				m_contactName.contentHeight + 2);
		}
	}

	override @property bool hidden() {
		return !m_initialized || super.hidden();
	}

	/// Rebuilds bearing and range for current ping source from ContactData
	void processNewPing(vec2d pingSourcePos)
	{
		returnMouseFocus();
		vec2d contactPos = data.data.position.contactPos;
		vec2d direction = contactPos - pingSourcePos;
		m_bearing = courseAngle(direction);
		m_range = direction.length;
		m_initialized = true;
	}

	private
	{
		/// True when m_bearing and range were initialized from ping source
		bool m_initialized;
		double m_bearing, m_range;
		CircleShape m_mainShape;
		Label m_contactName;
	}

	override void onPreDraw()
	{
		vec2d screenPos = owner.world2windowPos(vec2d(m_bearing, m_range));
		position = center2lu(screenPos);
		m_mainShape.center = cast(vec2f) screenPos;
		if (m_hovered)
		{
			m_contactName.position = vec2i(position.x + size.x / 2 - m_contactName.size.x / 2,
				position.y + size.y + 2);
			m_onHoverRect.center = cast(vec2f) screenPos;
			m_onHoverRect.size = cast(vec2f) size;
		}
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		if (m_hovered)
			m_onHoverRect.render(wnd);
		m_mainShape.render(wnd);
		if (m_hovered)
			m_contactName.draw(wnd, usecsDelta);
	}

	private void processMouseDown(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseLeft)
		{
			m_dragging = true;
			s_dragOffset = vec2i(x, y) - position;
			requestMouseFocus();
		}
	}

	private void processMouseUp(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseRight && !m_panning)
		{
			Button[] buttons = commonContactContextMenu(
				Game.simState.contactManager.get(data.ctcId));
			ContextMenu menu = contextMenu(
					Game.guiManager,
					buttons,
					Game.window.size,
					vec2i(x, y),
					20);
			return;
		}
		if (btn == sfMouseLeft && m_dragging)
		{
			m_dragging = false;
			if (!m_panning)
				returnMouseFocus();
			requestDataUpdate();
		}
	}

	/// Send updated data to cic
	private void requestDataUpdate()
	{
		vec2d pingSource = owner.outer.pingSourcePosition;
		vec2d newWorldPos = pingSource + m_range * courseVector(m_bearing);
		usecs_t newTime = owner.outer.pingTime;
		ContactData updated = data.cdata;
		if (newTime != data.cdata.time)
			updated.id = -1;	// different time = new data sample
		updated.time = newTime;
		updated.data.position.contactPos = newWorldPos;
		Game.ciccon.sendMessage(immutable CICContactDataReq(updated));
	}

	private void processMouseMove(int x, int y)
	{
		if (m_dragging)
		{
			vec2i newPos = vec2i(x, y) - s_dragOffset;
			vec2d newCenter = owner.clampInsideRect(lu2center(newPos));
			// we now need to update bearing and range from screen-space position
			vec2d newWorldCoord = owner.screen2worldPos(newCenter);
			m_bearing = newWorldCoord.x;
			m_range = newWorldCoord.y;
		}
	}
}



final class TacticalOverlay: Overlay
{
	private
	{
		CameraController m_camCtrl;
		int m_mousePrevX, m_mousePrevY;
		bool m_panned;	/// true when mouse has moved since RMB down
	}

	this(CameraController camCtrl)
	{
		m_camCtrl = camCtrl;
		mouseTransparent = false;
		// mouse and keyboard handlers
		onMouseDown += &processMouseDown;
		onMouseUp += &processMouseUp;
		onMouseMove += &processMouseMove;
		onMouseScroll += &processMouseScroll;
	}

	private void processMouseDown(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseRight)
		{
			onPanStart(x, y);
			requestMouseFocus();
		}
	}

	override void onPanStart(int x, int y)
	{
		m_panned = false;
		m_mousePrevX = x;
		m_mousePrevY = y;
	}

	private void processMouseUp(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseRight)
			returnMouseFocus();
	}

	private void processMouseMove(int x, int y)
	{
		if (mouseFocused)
			onPan(x, y);
	}

	override void onPan(int x, int y)
	{
		if (m_mousePrevX != x || m_mousePrevY != y)
			m_panned = true;	// we have moved the mouse
		m_camCtrl.onPan(x - m_mousePrevX, y - m_mousePrevY);
		m_mousePrevX = x;
		m_mousePrevY = y;
	}

	private void processMouseScroll(int x, int y, float delta)
	{
		m_camCtrl.onScroll(x, y, delta);
	}

	override vec2d world2windowPos(vec2d world)
	{
		return m_camCtrl.camera.transform2screen(world);
	}

	override double world2windowRot(double world)
	{
		return world - m_camCtrl.camera.rotation;
	}

	override vec2d screen2worldPos(vec2d screen)
	{
		return m_camCtrl.camera.transform2world(screen);
	}

	override double screen2worldRot(double screen)
	{
		return screen + m_camCtrl.camera.rotation;
	}
}


/// Icon above the player submarine
final class PlayerSubIcon: OverlayElement
{
	private
	{
		CircleShape m_shape;
		LineShape m_velLine;
		Submarine m_sub;
		enum sfColor BASE_COLOR = sfColor(51, 204, 255, 230);
		TacticalOverlay m_to;
	}

	this(TacticalOverlay to, Submarine sub)
	{
		assert(sub);
		super(to);
		m_to = to;
		m_sub = sub;
		size = vec2i(10, 10);
		m_shape = new CircleShape(5.0f, 12);
		m_shape.borderWidth = 2.0f;
		m_shape.borderColor = BASE_COLOR;
		m_velLine = new LineShape(vec2d(5.0f, 5.0f), vec2d(6.0f, 5.0f), BASE_COLOR, 2.0f);
	}

	private static sfColor getColorFromZoom(double zoom)
	{
		if (zoom >= 2.0)
			return sfTransparent;
		else if (zoom < 0.5)
			return BASE_COLOR;
		sfColor res = BASE_COLOR;
		res.a = (res.a * (1.0 - (zoom - 0.5) / 1.5)).to!ubyte;
		return res;
	}

	override void onPreDraw()
	{
		vec2d screenPos = m_to.world2windowPos(m_sub.transform.position);
		m_shape.center = cast(vec2f) screenPos;
		m_velLine.transform.position = vec2d(screenPos.x, -screenPos.y);
		position = center2lu(screenPos);
		KinematicSnapshot snap;
		if (m_sub.getInterpolatedSnapshot(snap))
		{
			double velRot = m_to.world2windowRot(courseAngle(snap.velocity));
			double velLen = 2.0 * snap.velocity.length;
			// LineShape is horizontal when transform rotation is zero, so we need
			// to add PI_2 in order to match it with dsubs rotation frame
			m_velLine.transform.rotation = velRot + PI_2;
			m_velLine.transform.scale = vec2d(velLen, 2.0f);
		}
		sfColor color = getColorFromZoom(m_to.m_camCtrl.camera.zoom);
		m_shape.borderColor = color;
		m_velLine.color = color;
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		m_shape.render(wnd);
		m_velLine.render(wnd);
	}
}


/// Contact has an overlay element in F1 tactical screen
final class TacticalContactElement: OverlayElementWithHover
{
	this(TacticalOverlay to, ClientContact contact)
	{
		m_contact = contact;
		super(to);
		m_onHoverRect = ctcOverlayCache.onHoverRect;
		updateFromContact();
		onMouseUp += &processMouseUp;
	}

	void updateFromContact()
	{
		m_mainShape = ctcOverlayCache.forContactType(m_contact.type);
		size = cast(vec2i) vec2f(2 * m_mainShape.radius + 4, 2 * m_mainShape.radius + 4);
		// contact id cannot change, so m_contactName is constant
		if (m_contactName is null)
		{
			m_contactName = new Label();
			m_contactName.fontSize = 15;
			m_contactName.content = m_contact.id.to!string;
			m_contactName.size = cast(vec2i) vec2f(m_contactName.contentWidth + 10,
				m_contactName.contentHeight + 2);
		}
	}

	private
	{
		ClientContact m_contact;
		CircleShape m_mainShape;
		RectangleShape m_onHoverRect;
		Label m_contactName;
		bool m_hovered = false;
	}

	private @property bool needDrawName()
	{
		return m_hovered || (m_contact.type != ContactType.environment &&
			m_contact.type != ContactType.decoy);
	}

	override @property bool hidden() {
		return !m_contact.solution.posAvailable || super.hidden();
	}

	override void onPreDraw()
	{
		vec2d worldPos = m_contact.solution.posData.contactPos;
		vec2d screenPos = owner.world2windowPos(worldPos);
		position = center2lu(screenPos);
		m_mainShape.center = cast(vec2f) screenPos;
		if (needDrawName)
		{
			m_contactName.position = vec2i(position.x + size.x / 2 - m_contactName.size.x / 2,
				position.y + size.y + 2);
		}
		if (m_hovered)
			m_onHoverRect.center = cast(vec2f) screenPos;
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		if (m_hovered)
			m_onHoverRect.render(wnd);
		m_mainShape.render(wnd);
		if (needDrawName)
			m_contactName.draw(wnd, usecsDelta);
	}

	private void processMouseUp(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseRight && !m_panning)
		{
			Button[] buttons = commonContactContextMenu(m_contact);
			ContextMenu menu = contextMenu(
					Game.guiManager,
					buttons,
					Game.window.size,
					vec2i(x, y),
					20);
			return;
		}
	}
}


/// Tactical overlay element, bound to positional data.
final class PositionDataTacticalElement: ContactDataOverlayElement
{
	this(TacticalOverlay owner, ClientContactData* data)
	{
		assert(data.type == DataType.Position);
		super(owner, data);
		m_mainShape = ctcOverlayCache.posDataMainShape;
		m_onHoverRect = ctcOverlayCache.posDataOnHoverRect;
	}

	private
	{
		RectangleShape m_mainShape;
		RectangleShape m_onHoverRect;
	}

	override void updateFromData() {}

	override void onPreDraw()
	{
		vec2d worldPos = data.data.posData.contactPos;
		vec2d screenPos = owner.world2windowPos(worldPos);
		position = center2lu(screenPos);
		m_mainShape.center = cast(vec2f) screenPos;
		if (m_hovered)
			m_onHoverRect.center = cast(vec2f) screenPos;
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		if (m_hovered)
			m_onHoverRect.render(wnd);
		m_mainShape.render(wnd);
	}
}