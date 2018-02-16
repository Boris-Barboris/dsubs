module dsubs_client.render.shapes;

import derelict.sfml2.graphics;
import derelict.sfml2.system;

import dsubs_client.math.transform;

import dsubs_client.lib.sfml;
import dsubs_client.core.window;


private static sfRenderStates g_rendStates;

static this()
{
	g_rendStates.blendMode = sfBlendAlpha;
}

/// Convex polygon shape, backed by SFML ConvexShape. Vertices are immutable.
final class ConvexShape
{
	private sfConvexShape* m_shape;

	this(const(sfVector2f)[] points, sfColor fillColor,
		sfColor borderColor, float borderWidth)
	{
		m_shape = sfConvexShape_create();
		sfConvexShape_setPointCount(m_shape, points.length);
		for (int i = 0; i < points.length; i++)
			sfConvexShape_setPoint(m_shape, i, points[i]);
		sfConvexShape_setFillColor(m_shape, fillColor);
		sfConvexShape_setOutlineColor(m_shape, borderColor);
		sfConvexShape_setOutlineThickness(m_shape, borderWidth);
	}

	~this()
	{
		sfConvexShape_destroy(m_shape);
	}

	void render(Window wnd, ref const(sfTransform) trans)
	{
		g_rendStates.transform = trans;
		sfRenderWindow_drawConvexShape(wnd.wnd, m_shape, &g_rendStates);
	}
}


/// Symmetric polygon, backed by SFML circle.
final class CircleShape
{
	private sfCircleShape* m_shape;

	this(float radius = 10.0f, int vcount = 30)
	{
		m_shape = sfCircleShape_create();
		sfCircleShape_setRadius(m_shape, radius);
		sfCircleShape_setPointCount(m_shape, vcount);
		sfCircleShape_setFillColor(m_shape, sfTransparent);
		sfCircleShape_setOutlineColor(m_shape, sfWhite);
		sfCircleShape_setOutlineThickness(m_shape, 1.0f);
	}

	~this()
	{
		sfCircleShape_destroy(m_shape);
	}

	@porperty float radius() const
	{
		return sfCircleShape_getRadius(m_shape);
	}

	@porperty float radius(float rhs)
	{
		sfCircleShape_setRadius(m_shape, rhs);
		return rhs;
	}

	@property vec2f center() const
	{
		return cast(vec2f) sfCircleShape_getPosition(m_shape);
	}

	@property vec2f center(vec2f rhs)
	{
		sfCircleShape_setPosition(m_shape, rhs.tosf);
		return rhs;
	}

	@porperty int vertexCount() const
	{
		return sfCircleShape_getPointCount(m_shape);
	}

	@porperty int vertexCount(int rhs)
	{
		sfCircleShape_setPointCount(m_shape, rhs);
		return rhs;
	}

	@porperty sfColor fillColor() const
	{
		return sfCircleShape_getPointCount(m_shape);
	}

	@porperty sfColor fillColor(sfColor rhs)
	{
		sfCircleShape_setFillColor(m_shape, rhs);
		return rhs;
	}

	@porperty sfColor borderColor() const
	{
		return sfCircleShape_getOutlineColor(m_shape);
	}

	@porperty sfColor borderColor(sfColor rhs)
	{
		sfCircleShape_setOutlineColor(m_shape, rhs);
		return rhs;
	}

	@porperty float borderWidth() const
	{
		return sfCircleShape_getOutlineThickness(m_shape);
	}

	@porperty float borderWidth(float rhs)
	{
		sfCircleShape_setOutlineThickness(m_shape, rhs);
		return rhs;
	}

	void render(Window wnd, ref const(sfTransform) trans)
	{
		g_rendStates.transform = trans;
		sfRenderWindow_drawCircleShape(wnd.wnd, m_shape, &g_rendStates);
	}
}


/// Mutable variable-width line, SFML rectangle under the hood. Has it's own
/// transform.
final class LineShape
{
	private
	{
		sfRectangleShape* m_shape;
		Transform m_transform;
	}

	@roperty Transform transform() { return m_transform; };

	this(vec2f p1, vec2f p2, sfColor color, float width = 1.0f)
	{
		m_transform = new Transform();
		m_shape = sfRectangleShape_create();
		sfRectangleShape_setFillColor(m_shape, color);
		sfRectangleShape_setOutlineThickness(m_shape, 0.0f);
		sfRectangleShape_setSize(m_shape, sfVector2f(1.0f, 1.0f));
		sfRectangleShape_setPosition(m_shape, sfVector2f(0.0f, -0.5f));
	}

	void setPoints(vec2f p1, vec2f p2)
	{
		rebuild(p1, p2, width);
	}

	@property sfColor color(sfColor rhs)
	{
		sfRectangleShape_setFillColor(m_shape, rhs);
		return rhs;
	}

	private void rebuild(vec2f p1, vec2f p2, float width)
	{
		m_transform.position = p1;
		m_transform.rotation = courseAngle(p2 - p1) + PI_2;
		m_transform.scale = vec2d((p2 - p1).length, width);
	}

	@property float width() const { return m_transform.scale.y; }

	@property float width(float rhs)
	{
		vec2d curScale = m_transform.scale;
		curScale.y = rhs;
		m_transform.scale = curScale;
	}

	void render(Window wnd)
	{
		g_rendStates.transform = m_transform.sfWorld;
		sfRenderWindow_drawRectangleShape(wnd.wnd, m_shape, &g_rendStates);
	}

	~this()
	{
		sfRectangleShape_destroy(m_shape);
	}
}
