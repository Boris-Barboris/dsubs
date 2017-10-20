module dsubs_client.world.convex;

import derelict.sfml2.graphics;
import derelict.sfml2.system;

import dsubs_client.lib.sfml;
import dsubs_client.core.window;


class ConvexShape
{
	protected
	{
		sfConvexShape* shape;
	}

	package static sfRenderStates state_template;

	static this()
	{
		state_template.blendMode = sfBlendAlpha;
	}

	this(sfVector2f[] points, sfColor fill_color,
		sfColor border_color, float border_width)
	{
		shape = sfConvexShape_create();
		sfConvexShape_setPointCount(shape, points.length);
		for (int i = 0; i < points.length; i++)
			sfConvexShape_setPoint(shape, i, points[i]);
		sfConvexShape_setFillColor(shape, fill_color);
		sfConvexShape_setOutlineColor(shape, border_color);
		sfConvexShape_setOutlineThickness(shape, border_width);
	}

	~this()
	{
		sfConvexShape_destroy(shape);
	}

	void render(Window wnd, const sfTransform trans)
	{
		state_template.transform = trans;
		sfRenderWindow_drawConvexShape(wnd.ptr, shape, &state_template);
	}
}
