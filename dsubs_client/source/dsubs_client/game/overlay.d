module dsubs_client.game.overlay;

import std.conv: to;
import std.math;
import std.experimental.logger;

import derelict.sfml2.graphics;

import dsubs_common.math;

import dsubs_client.core.window;
import dsubs_client.render.shapes;
import dsubs_client.render.worldmanager;
import dsubs_client.math.transform;

import dsubs_client.game.entities;
import dsubs_client.game.kinetic;



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
		static immutable sfColor BASE_COLOR = sfColor(51, 204, 255, 230);
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
			double velLen = 1.33 * snap.velocity.length;
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
		m_shape.render(wnd, transform.sfWorld);
		m_velLine.render(wnd);
	}
}