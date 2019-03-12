module dsubs_client.render.shapes;

import derelict.sfml2.graphics;
import derelict.sfml2.system;

import dsubs_client.math.transform;

import dsubs_client.lib.sfml;
import dsubs_client.core.window;


abstract class Shape
{
	protected sfRenderStates m_rendStates;

	this()
	{
		m_rendStates.blendMode = sfBlendAlpha;
	}

	void render(Window wnd);
	void render(Window wnd, const mat3x3d trans);
	void render(Window wnd, const sfTransform trans);
}

/// Convex polygon shape, backed by SFML ConvexShape. Vertices are immutable.
final class ConvexShape: Shape
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

	override void render(Window wnd)
	{
		m_rendStates.transform = sfTransform_Identity;
		sfRenderWindow_drawConvexShape(wnd.wnd, m_shape, &m_rendStates);
	}

	override void render(Window wnd, const mat3x3d trans)
	{
		m_rendStates.transform = trans.tosf;
		sfRenderWindow_drawConvexShape(wnd.wnd, m_shape, &m_rendStates);
	}

	override void render(Window wnd, const sfTransform trans)
	{
		m_rendStates.transform = trans;
		sfRenderWindow_drawConvexShape(wnd.wnd, m_shape, &m_rendStates);
	}
}


/// Symmetric polygon, backed by SFML circle.
final class CircleShape: Shape
{
	private sfCircleShape* m_shape;

	this(float radius = 10.0f, int vcount = 30, sfColor color = sfWhite,
		float borderW = 1.0f)
	{
		m_shape = sfCircleShape_create();
		sfCircleShape_setRadius(m_shape, radius);
		sfCircleShape_setPointCount(m_shape, vcount);
		sfCircleShape_setFillColor(m_shape, sfTransparent);
		sfCircleShape_setOutlineColor(m_shape, color);
		sfCircleShape_setOutlineThickness(m_shape, borderW);
		sfCircleShape_setOrigin(m_shape, sfVector2f(radius, radius));
	}

	~this()
	{
		sfCircleShape_destroy(m_shape);
	}

	@property float radius() const
	{
		return sfCircleShape_getRadius(m_shape);
	}

	@property float radius(float rhs)
	{
		sfCircleShape_setRadius(m_shape, rhs);
		sfCircleShape_setOrigin(m_shape, sfVector2f(rhs, rhs));
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

	@property size_t vertexCount() const
	{
		return sfCircleShape_getPointCount(m_shape);
	}

	@property size_t vertexCount(int rhs)
	{
		sfCircleShape_setPointCount(m_shape, rhs);
		return rhs;
	}

	@property sfColor fillColor() const
	{
		return sfCircleShape_getFillColor(m_shape);
	}

	@property sfColor fillColor(sfColor rhs)
	{
		sfCircleShape_setFillColor(m_shape, rhs);
		return rhs;
	}

	@property sfColor borderColor() const
	{
		return sfCircleShape_getOutlineColor(m_shape);
	}

	@property sfColor borderColor(sfColor rhs)
	{
		sfCircleShape_setOutlineColor(m_shape, rhs);
		return rhs;
	}

	@property float borderWidth() const
	{
		return sfCircleShape_getOutlineThickness(m_shape);
	}

	@property float borderWidth(float rhs)
	{
		sfCircleShape_setOutlineThickness(m_shape, rhs);
		return rhs;
	}

	override void render(Window wnd)
	{
		m_rendStates.transform = sfTransform_Identity;
		sfRenderWindow_drawCircleShape(wnd.wnd, m_shape, &m_rendStates);
	}

	override void render(Window wnd, const mat3x3d trans)
	{
		m_rendStates.transform = trans.tosf;
		sfRenderWindow_drawCircleShape(wnd.wnd, m_shape, &m_rendStates);
	}

	override void render(Window wnd, const sfTransform trans)
	{
		m_rendStates.transform = trans;
		sfRenderWindow_drawCircleShape(wnd.wnd, m_shape, &m_rendStates);
	}
}


final class RectangleShape: Shape
{
	private sfRectangleShape* m_shape;

	this(vec2f size, sfColor borderCol,
		sfColor fillColor = sfTransparent, float borderW = 1.0f)
	{
		m_shape = sfRectangleShape_create();
		sfRectangleShape_setSize(m_shape, size.tosf);
		sfRectangleShape_setOutlineColor(m_shape, borderCol);
		sfRectangleShape_setFillColor(m_shape, fillColor);
		sfRectangleShape_setOutlineThickness(m_shape, borderW);
	}

	@property vec2f position() const
	{
		return cast(vec2f) sfRectangleShape_getPosition(m_shape);
	}

	@property vec2f position(vec2f rhs)
	{
		sfRectangleShape_setPosition(m_shape, rhs.tosf);
		return rhs;
	}

	@property vec2f size() const
	{
		return cast(vec2f) sfRectangleShape_getSize(m_shape);
	}

	@property vec2f size(vec2f rhs)
	{
		sfRectangleShape_setSize(m_shape, rhs.tosf);
		return rhs;
	}

	@property sfColor fillColor() const
	{
		return sfRectangleShape_getFillColor(m_shape);
	}

	@property sfColor fillColor(sfColor rhs)
	{
		sfRectangleShape_setFillColor(m_shape, rhs);
		return rhs;
	}

	@property sfColor borderColor() const
	{
		return sfRectangleShape_getOutlineColor(m_shape);
	}

	@property sfColor borderColor(sfColor rhs)
	{
		sfRectangleShape_setOutlineColor(m_shape, rhs);
		return rhs;
	}

	@property float borderWidth() const
	{
		return sfRectangleShape_getOutlineThickness(m_shape);
	}

	@property float borderWidth(float rhs)
	{
		sfRectangleShape_setOutlineThickness(m_shape, rhs);
		return rhs;
	}

	override void render(Window wnd)
	{
		m_rendStates.transform = sfTransform_Identity;
		sfRenderWindow_drawRectangleShape(wnd.wnd, m_shape, &m_rendStates);
	}

	override void render(Window wnd, const mat3x3d trans)
	{
		m_rendStates.transform = trans.tosf;
		sfRenderWindow_drawRectangleShape(wnd.wnd, m_shape, &m_rendStates);
	}

	override void render(Window wnd, const sfTransform trans)
	{
		m_rendStates.transform = trans;
		sfRenderWindow_drawRectangleShape(wnd.wnd, m_shape, &m_rendStates);
	}

	~this()
	{
		sfRectangleShape_destroy(m_shape);
	}
}


/// Mutable variable-width line,
/// SFML rectangle under the hood. Has it's own transform.
final class LineShape: Shape
{
	private
	{
		sfRectangleShape* m_shape;
		Transform m_transform;
	}

	@property Transform transform() { return m_transform; }

	this(vec2d p1, vec2d p2, sfColor color, float width = 1.0f)
	{
		m_transform = new Transform();
		m_shape = sfRectangleShape_create();
		sfRectangleShape_setFillColor(m_shape, color);
		sfRectangleShape_setOutlineThickness(m_shape, 0.0f);
		sfRectangleShape_setSize(m_shape, sfVector2f(1.0f, 1.0f));
		sfRectangleShape_setPosition(m_shape, sfVector2f(0.0f, -0.5f));
		rebuild(p1, p2, width);
	}

	void setPoints(vec2d p1, vec2d p2)
	{
		rebuild(p1, p2, width);
	}

	@property sfColor color(sfColor rhs)
	{
		sfRectangleShape_setFillColor(m_shape, rhs);
		return rhs;
	}

	private void rebuild(vec2d p1, vec2d p2, float width)
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
		return rhs;
	}

	override void render(Window wnd)
	{
		m_rendStates.transform = m_transform.world.tosf;
		sfRenderWindow_drawRectangleShape(wnd.wnd, m_shape, &m_rendStates);
	}

	override void render(Window wnd, const mat3x3d trans)
	{
		m_rendStates.transform = tosf(trans * m_transform.world);
		sfRenderWindow_drawRectangleShape(wnd.wnd, m_shape, &m_rendStates);
	}

	override void render(Window wnd, const sfTransform trans)
	{
		m_rendStates.transform = tosf(trans.togfm * m_transform.world);
		sfRenderWindow_drawRectangleShape(wnd.wnd, m_shape, &m_rendStates);
	}

	~this()
	{
		sfRectangleShape_destroy(m_shape);
	}
}
