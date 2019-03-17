module dsubs_client.game.overlay;

import std.conv: to;
import std.math;
import std.experimental.logger;

import core.time;

import derelict.sfml2.graphics;

import dsubs_common.math;
import dsubs_common.mutstring;

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
		m_posDataMainShape = new RectangleShape(vec2f(5, 5), sfRed);
		m_posDataOnHoverRect = new RectangleShape(vec2f(12.0f, 12.0f), sfWhite);
		m_posDataOnHoverRect.position = -vec2f(1, 1);
		m_velCircle = new CircleShape(40.0f, 30, sfWhite, 3);
		m_velDragLine = new LineShape(vec2d(0, 0), vec2d(0, 0), sfColor(137, 182, 255, 255), 5);
	}

	private
	{
		CircleShape[ContactType.max + 1] m_shapes;
	}

	mixin Readonly!(RectangleShape, "onHoverRect");
	mixin Readonly!(RectangleShape, "posDataMainShape");
	mixin Readonly!(RectangleShape, "posDataOnHoverRect");
	mixin Readonly!(CircleShape, "velCircle");
	mixin Readonly!(LineShape, "velDragLine");

	CircleShape forContactType(ContactType t)
	{
		return m_shapes[t];
	}
}


pragma(inline)
private ContactOverlayShapeCahe ctcOverlayCache()
{
	return Game.simState.contactOverlayShapeCache;
}

private __gshared vec2i g_dragOffset;


/// Overlay element that draws a rectange when the mouse hovers over it
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

/// Overlay element that is bound to ClientContactData.
class ContactDataOverlayElement: OverlayElementWithHover
{
	this(Overlay owner, ClientContactData* data)
	{
		m_data = data;
		super(owner);
	}

	mixin Readonly!(ClientContactData*, "data");

	/// When the contact data updates from CIC message, this method is called;
	abstract void updateFromData();
}

/// Active sonar data sample on sonar display.
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
			m_contactName.enableScissorTest = false;
			m_contactName.fontSize = 15;
			m_contactName.content = contact.id.to!string;
			m_contactName.fontColor = sfRed;
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
			g_dragOffset = vec2i(x, y) - position;
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
		if (newTime != data.time)
			updated.id = -1;	// different time = new data sample
		updated.time = newTime;
		updated.data.position.contactPos = newWorldPos;
		Game.ciccon.sendMessage(immutable CICContactDataReq(updated));
	}

	private void processMouseMove(int x, int y)
	{
		if (m_dragging)
		{
			vec2i newPos = vec2i(x, y) - g_dragOffset;
			vec2d newCenter = owner.clampInsideRect(lu2center(newPos));
			// we now need to update bearing and range from screen-space position
			vec2d newWorldCoord = owner.screen2worldPos(newCenter);
			m_bearing = newWorldCoord.x;
			m_range = newWorldCoord.y;
		}
	}
}


/// Main overlay of F1 screen
final class TacticalOverlay: Overlay
{
	private
	{
		CameraController m_camCtrl;
		int m_mousePrevX, m_mousePrevY;
		bool m_panned;	/// true when mouse has moved since RMB down
		TacticalContactElement m_selectedContact;
		ContactDataOverlayElement[int] m_selectedContactData;
		Label m_mergeHint;
	}

	this(CameraController camCtrl)
	{
		m_camCtrl = camCtrl;
		mouseTransparent = false;
		m_mergeHint = new Label();
		m_mergeHint.fontSize = 25;
		m_mergeHint.fontColor = sfColor(255, 255, 255, 50);
		m_mergeHint.htextAlign = HTextAlign.CENTER;
		m_mergeHint.vtextAlign = VTextAlign.CENTER;
		m_mergeHint.content = "Click on the contact to merge into";
		m_mergeHint.mouseTransparent = true;
		m_mergeHint.size = cast(vec2i) vec2f(
			m_mergeHint.contentWidth(), m_mergeHint.contentHeight());
		// mouse and keyboard handlers
		onMouseDown += &processMouseDown;
		onMouseUp += &processMouseUp;
		onMouseMove += &processMouseMove;
		onMouseScroll += &processMouseScroll;
	}

	override void updatePosition()
	{
		super.updatePosition();
		m_mergeHint.position = position + (size - m_mergeHint.size) / 2;
	}

	override void updateSize()
	{
		super.updateSize();
		m_mergeHint.position = position + (size - m_mergeHint.size) / 2;
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
		if (btn == sfMouseLeft)
			selectedContact = null;
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

	@property TacticalContactElement selectedContact() { return m_selectedContact; }

	@property void selectedContact(TacticalContactElement rhs)
	{
		// we need to start drawing all data of this contact
		if (rhs is m_selectedContact)
			return;
		trace("setting owner to ", rhs);
		if (m_selectedContact !is null)
		{
			// clear all data of this contact
			foreach (ContactDataOverlayElement el; m_selectedContactData.byValue)
				el.onHide();
			m_selectedContactData.clear();
		}
		if (rhs !is null)
		{
			// generate data for this contact
			foreach (ClientContactData* ctd; rhs.contact.contactDataRange)
			{
				ContactDataOverlayElement newElement;
				switch (ctd.type)
				{
					case (DataType.Position):
						newElement = new PositionDataTacticalElement(this, ctd);
						break;
					default:
						break;
				}
				m_selectedContactData[ctd.id] = newElement;
			}
		}
		m_selectedContact = rhs;
	}

	/// Completely new contact data must be rendered for selectedContact
	void addSelectedContactData(ClientContactData* ctd)
	{
		ContactDataOverlayElement newElement;
		switch (ctd.type)
		{
			case (DataType.Position):
				newElement = new PositionDataTacticalElement(this, ctd);
				break;
			default:
				break;
		}
		m_selectedContactData[ctd.id] = newElement;
	}

	/// Contact data must no longer be rendered for selectedContact
	void dropSelectedContactData(int id)
	{
		ContactDataOverlayElement* existing = id in m_selectedContactData;
		if (existing)
		{
			existing.onHide();
			m_selectedContactData.remove(id);
		}
	}

	override void add(OverlayElement el)
	{
		ContactDataOverlayElement cdoe = cast(ContactDataOverlayElement) el;
		if (cdoe)
		{
			m_selectedContactData[cdoe.data.id] = cdoe;
			return;
		}
		m_elements[el] = true;
	}

	override void remove(OverlayElement el)
	{
		ContactDataOverlayElement cdoe = cast(ContactDataOverlayElement) el;
		if (cdoe)
		{
			m_selectedContactData.remove(cdoe.data.id);
			if (!cdoe.hidden)
				cdoe.onHide();
			return;
		}
		if (selectedContact is el)
			selectedContact = null;
		super.remove(el);
	}

	override void onHide()
	{
		super.onHide();
		foreach (ContactDataOverlayElement el; m_selectedContactData.byValue)
		{
			if (!el.hidden)
				el.onHide();
		}
		g_inMerge = false;
	}

	override void draw(Window wnd, long usecsDelta)
	{
		if (hidden)
			return;
		super.draw(wnd, usecsDelta);
		foreach (ContactDataOverlayElement el; m_selectedContactData.byValue)
		{
			if (!el.hidden)
			{
				el.onPreDraw();
				el.draw(wnd, usecsDelta);
			}
		}
		if (g_inMerge)
			m_mergeHint.draw(wnd, usecsDelta);
	}

	override GuiElement getFromPoint(const sfEvent* evt, int x, int y)
	{
		if (hidden)
			return null;
		if (rectContainsPoint(x, y))
		{
			foreach (ContactDataOverlayElement el; m_selectedContactData.byValue)
			{
				if (!el.hidden)
				{
					GuiElement res = el.getFromPoint(evt, x, y);
					if (res)
						return res;
				}
			}
			foreach (OverlayElement el; m_elements.byKey)
			{
				if (!el.hidden)
				{
					GuiElement res = el.getFromPoint(evt, x, y);
					if (res)
						return res;
				}
			}
			return this;
		}
		return null;
	}
}


/// Icon and velocity vector above the player submarine
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

private __gshared
{
	bool g_inMerge;
	ContactId g_mergeSourceId;
}


/// Contact's icon on F1 screen
final class TacticalContactElement: OverlayElementWithHover
{
	this(TacticalOverlay to, ClientContact contact)
	{
		m_contact = contact;
		m_solution = contact.solution;
		super(to);
		m_onHoverRect = ctcOverlayCache.onHoverRect;
		m_velCircle = ctcOverlayCache.velCircle;
		m_velDragLine = ctcOverlayCache.velDragLine;
		updateFromContact();
		onMouseUp += &processMouseUp;
		onMouseMove += &processMouseMove;
		onMouseDown += &processMouseDown;

		if (g_velLabel is null)
		{
			g_velLabel = new Label();
			g_velLabel.mouseTransparent = true;
			g_velLabel.fontSize = 12;
			g_velLabel.htextAlign = HTextAlign.LEFT;
			g_velLabel.vtextAlign = VTextAlign.CENTER;
			g_velLabel.size = vec2i(60, 16);
			g_velLabel.enableScissorTest = false;
		}
	}

	void updateFromContact()
	{
		m_mainShape = ctcOverlayCache.forContactType(m_contact.type);
		size = cast(vec2i) vec2f(2 * m_mainShape.radius + 4, 2 * m_mainShape.radius + 4);
		// contact id cannot change, so m_contactName is constant
		if (m_contactName is null)
		{
			m_contactName = new Label();
			m_contactName.enableScissorTest = false;
			m_contactName.fontSize = 15;
			m_contactName.content = m_contact.id.to!string;
			m_contactName.size = cast(vec2i) vec2f(m_contactName.contentWidth + 10,
				m_contactName.contentHeight + 2);
		}
	}

	private
	{
		ClientContact m_contact;
		ContactSolution m_solution;
		CircleShape m_mainShape, m_velCircle;
		RectangleShape m_onHoverRect;
		LineShape m_velDragLine;
		Label m_contactName;
		vec2d m_lastScreenPos;
		bool m_velDragMode;
	}

	private __gshared Label g_velLabel;

	@property ClientContact contact() { return m_contact; }

	private @property bool needDrawName()
	{
		return m_hovered || (m_contact.type != ContactType.environment &&
			m_contact.type != ContactType.decoy);
	}

	override @property bool hidden()
	{
		return !m_contact.solution.posAvailable || super.hidden();
	}

	@property bool isSelected()
	{
		return tacowner.selectedContact is this;
	}

	/// Overlay elements must ignore mouse scroll in order to not block zooming
	override GuiElement getFromPoint(const sfEvent* evt, int x, int y)
	{
		if (evt.type == sfEvtMouseWheelScrolled)
			return null;
		// velCircle check
		if (isSelected)
		{
			// check if cursor is inside the circle
			if (pointOnCircle(vec2i(x, y)))
				return this;
		}
		return GuiElement.getFromPoint(evt, x, y);
	}

	private bool pointOnCircle(vec2i point)
	{
		double rad = (m_lastScreenPos - point).length;
		return (rad >= (m_velCircle.radius - 3) &&
				rad <= (m_velCircle.radius + m_velCircle.borderWidth + 3));
	}

	private double secsSinceSolution()
	{
		usecs_t usecsSince =
			Game.simState.lastServerTime +
			(MonoTime.currTime - Game.simState.lastServerTimeOnClient).total!"usecs" -
			m_contact.solution.time;
		return usecsSince / 1.0e6;
	}

	override void onPreDraw()
	{
		if (!isSelected)
		{
			m_solution = m_contact.solution;
			if (m_solution.velAvailable)
				m_solution.pos += secsSinceSolution * m_solution.vel;
		}
		vec2d worldPos = m_solution.pos;
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
		if (isSelected)
		{
			m_velCircle.center = cast(vec2f) screenPos;
			if (m_solution.velAvailable)
			{
				double speed = m_solution.vel.length;
				double vecLen = speed2lineLength(speed);
				vec2d velDelta = speed > 1e-3 ?
					m_solution.vel.normalized * vecLen :
					vec2d(0, 0);
				velDelta.y = - velDelta.y;
				vec2d point2 = screenPos + velDelta;
				m_velDragLine.setPoints(screenPos, point2, true);
				g_velLabel.position = cast(vec2i) vec2d(point2.x + 15, point2.y);
				dmutstring spdStr = g_velLabel.content;
				mutsformat!"%.2f m/s"(spdStr, speed);
				g_velLabel.content = spdStr;
			}
		}
		m_lastScreenPos = screenPos;
	}

	private enum double PIXEL_PER_MPS = 8;
	private enum double ZERO_SPD_PIXEL_MARGIN = 15;

	private static double lineLength2speed(double len)
	{
		if (len < ZERO_SPD_PIXEL_MARGIN)
			return 0.0;
		return (len - ZERO_SPD_PIXEL_MARGIN) / PIXEL_PER_MPS;
	}

	private static double speed2lineLength(double speed)
	{
		return ZERO_SPD_PIXEL_MARGIN + speed * PIXEL_PER_MPS;
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		if (isSelected)
		{
			if (m_solution.velAvailable)
			{
				m_velDragLine.render(wnd);
				g_velLabel.draw(wnd, usecsDelta);
			}
			if (!m_dragging)
			{
				if (m_hovered)
					m_velCircle.borderColor = sfRed;
				else
					m_velCircle.borderColor = sfWhite;
				m_velCircle.render(wnd);
			}
		}
		if (m_hovered)
			m_onHoverRect.render(wnd);
		m_mainShape.render(wnd);
		if (needDrawName)
			m_contactName.draw(wnd, usecsDelta);
	}

	@property TacticalOverlay tacowner() { return cast(TacticalOverlay) owner; }

	private void processMouseUp(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseLeft)
		{
			if (m_dragging)
			{
				m_dragging = false;
				m_velDragMode = false;
				if (!m_panning)
					returnMouseFocus();
				m_contact.m_ctc.solution = m_solution;
				requestSolutionUpdate();
			}
			if (!m_panning)
			{
				if (g_inMerge)
				{
					if (g_mergeSourceId != m_contact.id)
						Game.ciccon.sendMessage(immutable CICContactMergeReq(
							g_mergeSourceId, m_contact.id));
					g_inMerge = false;
				}
				else
				{
					m_solution.time = Game.simState.lastServerTime +
						(MonoTime.currTime - Game.simState.lastServerTimeOnClient).total!"usecs";
					tacowner.selectedContact = this;
				}
			}
		}
		if (btn == sfMouseRight && !m_panning)
		{
			Button[] buttons = commonContactContextMenu(m_contact);
			// add merge to button
			Button mbtn = builder(new Button()).fontSize(15).content("merge into").build();
			mbtn.onClick += {
				g_inMerge = true;
				g_mergeSourceId = m_contact.id;
			};
			buttons ~= mbtn;
			ContextMenu menu = contextMenu(
					Game.guiManager,
					buttons,
					Game.window.size,
					vec2i(x, y),
					20);
			return;
		}
	}

	private void processMouseMove(int x, int y)
	{
		if (m_dragging)
		{
			if (m_velDragMode)
			{
				// velocity dragging
				vec2d center = m_mainShape.center;
				vec2d delta = vec2d(x, y) - center;
				delta.y = -delta.y;	// screen-space y
				double lineLen = delta.length;
				double speed = lineLength2speed(lineLen);
				m_solution.velAvailable = true;
				if (speed > 0.001)
					m_solution.vel = speed * delta.normalized;
				else
					m_solution.vel = vec2d(0, 0);
			}
			else
			{
				vec2i newPos = vec2i(x, y) - g_dragOffset;
				vec2d newCenter = owner.clampInsideRect(lu2center(newPos));
				// we now need to update bearing and range from screen-space position
				vec2d newWorldCoord = owner.screen2worldPos(newCenter);
				m_solution.posAvailable = true;
				m_solution.pos = newWorldCoord;
			}
		}
	}

	/// Send updated solution to CIC
	private void requestSolutionUpdate()
	{
		Game.ciccon.sendMessage(immutable CICContactUpdateReq(contact.m_ctc));
	}

	override void drop()
	{
		if (g_inMerge && m_contact.id == g_mergeSourceId)
			g_inMerge = false;
		super.drop();
	}

	void addData(ClientContactData* cdata)
	{
		if (isSelected)
			tacowner.addSelectedContactData(cdata);
	}

	void removeData(int id)
	{
		if (isSelected)
			tacowner.dropSelectedContactData(id);
	}

	private void processMouseDown(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseLeft && isSelected)
		{
			m_dragging = true;
			g_dragOffset = vec2i(x, y) - position;
			m_velDragMode = pointOnCircle(vec2i(x, y));
			requestMouseFocus();
		}
	}
}


class DataTacticalElement: ContactDataOverlayElement
{
	this(TacticalOverlay owner, ClientContactData* data)
	{
		super(owner, data);
		onMouseUp += &processMouseUp;
	}

	private void processMouseUp(int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseRight && !m_panning)
		{
			Button[] buttons = dataContextMenuOptions();
			ContextMenu menu = contextMenu(
					Game.guiManager,
					buttons,
					Game.window.size,
					vec2i(x, y),
					20);
			return;
		}
	}

	protected Button[] dataContextMenuOptions()
	{
		Button[] res;
		Button btn = builder(new Button()).fontSize(15).content("drop data sample").build();
		btn.onClick += {
			Game.ciccon.sendMessage(immutable CICDropDataReq(data.id));
		};
		res ~= btn;
		return res;
	}
}

/// Tactical overlay element, bound to positional data.
final class PositionDataTacticalElement: DataTacticalElement
{
	this(TacticalOverlay owner, ClientContactData* data)
	{
		assert(data.type == DataType.Position);
		super(owner, data);
		m_mainShape = ctcOverlayCache.posDataMainShape;
		m_onHoverRect = ctcOverlayCache.posDataOnHoverRect;
		size = cast(vec2i) (m_onHoverRect.size + vec2f(2, 2));
	}

	private
	{
		RectangleShape m_mainShape;
		RectangleShape m_onHoverRect;
	}

	override void updateFromData() {}

	override void onPreDraw()
	{
		vec2d worldPos = data.data.position.contactPos;
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