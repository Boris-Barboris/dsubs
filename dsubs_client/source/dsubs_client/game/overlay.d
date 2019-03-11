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
import dsubs_client.game.cic.messages;
import dsubs_client.game.entities;
import dsubs_client.game.kinetic;
import dsubs_client.game.contacts;




final class ContactOverlayShapeCahe
{
	this()
	{
		m_shapes[ContactType.Unknown] =
			new CircleShape(10.0f, 4, sfColor(244, 241, 66, 255));
		m_shapes[ContactType.Environment] =
			new CircleShape(8.0f, 6, sfColor(107, 244, 65, 255));
		m_shapes[ContactType.Submarine] =
			new CircleShape(10.0f, 12, sfColor(255, 132, 10, 255));
		m_shapes[ContactType.Weapon] =
			new CircleShape(8.0f, 3, sfRed);
		m_shapes[ContactType.Decoy] =
			new CircleShape(8.0f, 5, sfColor(152, 9, 255, 255));
	}

	private
	{
		CircleShape[ContactType.max + 1] m_shapes;
	}

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


class ContactDataOverlayElement: OverlayElement
{
	this(Overlay owner, ClientContactData* data)
	{
		super(owner);
		m_data = data;
	}

	mixin Readonly!(ClientContactData*, "data");
}

class SonarDispContactDataElement: ContactDataOverlayElement
{
	this(Overlay owner, ClientContactData* data, ClientContact contact)
	{
		assert(data.data.type == DataType.Position);
		assert(data.data.source.type == DataSourceType.ActiveSonar);
		assert(data.data.source.sensorIdx == 0);
		super(owner, data);
		// we need to calculate bearing and range in order to be able to draw it
		BodySnapshot lastSnap;
		enforce(Game.simState.playerSub.getLastSnapshot(lastSnap));
		vec2d contactPos = data.data.data.position.contactPos;
		vec2d direction = contactPos - lastSnap.position;
		m_bearing = courseAngle(direction);
		m_range = direction.length;
		m_mainShape = ctcOverlayCache.forContactType(contact.data.type);
		size = vec2i(20, 20);
		m_mainShape.center = vec2f(10.0f, 10.0f);
	}

	private
	{
		double m_bearing, m_range;
		CircleShape m_mainShape;
	}

	override void onPreDraw()
	{
		position = center2lu(owner.world2screenPos(vec2d(m_bearing, m_range)));
	}

	override void draw(Window wnd, long usecsDelta)
	{
		super.draw(wnd, usecsDelta);
		m_mainShape.render(wnd, m_sfRst.transform);
	}
}


class OverlayEntity: WorldRenderable
{
	private
	{
		double prevZoom;
		double prevRot;
	}

	override void update(CameraContext camCtx, long usecsDelta)
	{
		if (prevZoom != camCtx.camera.zoom || prevRot != camCtx.camera.rotation)
		{
			// camera has changed in a way that requires transform update
			prevZoom = camCtx.camera.zoom;
			double scaleX = 1.0 / prevZoom;
			assert(!isNaN(scaleX));
			transform.scale = vec2d(scaleX, scaleX);
			prevRot = camCtx.camera.rotation;
			transform.rotation = prevRot;
		}
		super.update(camCtx, usecsDelta);
	}
}


/// Icon above the player submarine
final class PlayerSubIcon: OverlayEntity
{
	private
	{
		CircleShape m_shape;
		LineShape m_velLine;
		Submarine m_sub;
		enum sfColor BASE_COLOR = sfColor(51, 204, 255, 230);
	}

	this(Submarine sub)
	{
		assert(sub);
		m_sub = sub;
		m_shape = new CircleShape(5.0f, 12);
		m_shape.borderWidth = 2.0f;
		m_shape.borderColor = BASE_COLOR;
		m_velLine = new LineShape(vec2f(0.0f, 0.0f), vec2f(0.0f, 0.0f), BASE_COLOR, 2.0f);
		transform.addChild(m_velLine.transform);
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

	override void update(CameraContext camCtx, long usecsDelta)
	{
		super.update(camCtx, usecsDelta);
		transform.position = m_sub.transform.position;
		BodySnapshot snap;
		if (m_sub.getInterpolatedSnapshot(snap))
		{
			double velRot = courseAngle(snap.velocity);
			double velLen = 2.0 * snap.velocity.length;
			// LineShape is horizontal when transform rotation is zero, so we need
			// to add PI_2 in order to match it with dsubs rotation frame
			m_velLine.transform.rotation = -transform.rotation + velRot + PI_2;
			m_velLine.transform.scale = vec2d(velLen, 2.0f);
		}
		sfColor color = getColorFromZoom(camCtx.camera.zoom);
		m_shape.borderColor = color;
		m_velLine.color = color;
	}

	override void render(Window wnd)
	{
		m_shape.render(wnd, transform.world);
		m_velLine.render(wnd, );
	}
}