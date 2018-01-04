module dsubs_client.render.convex;

import derelict.sfml2.graphics;
import derelict.sfml2.system;

import dsubs_client.lib.sfml;
import dsubs_client.core.window;


class ConvexShape
{
	protected
	{
		sfConvexShape* m_shape;
	}

	private static sfRenderStates g_rendStates;

	static this()
	{
		g_rendStates.blendMode = sfBlendAlpha;
	}

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

	void render(Window wnd, const ref sfTransform trans)
	{
		g_rendStates.transform = trans;
		sfRenderWindow_drawConvexShape(wnd.wnd, m_shape, &g_rendStates);
	}
}
