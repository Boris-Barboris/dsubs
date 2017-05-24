module dsubs_client.world.convex;

import derelict.sfml2.graphics;
import derelict.sfml2.system;

import dsubs_common.math.transform;

import dsubs_client.core.sfml;
import dsubs_client.core.window;


class ConvexShape
{
	Transform2D transform;
	protected
	{
		sfConvexShape* shape;
	}

	protected sfRenderStates state_template;

	this(sfVector2f[] points, sfColor fill_color,
		sfColor border_color, float border_width)
	{
		state_template.blendMode = sfBlendAlpha;
		transform = new Transform2D();
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
		if (shape)
		{
			sfConvexShape_destroy(shape);
			shape = null;
		}
	}

	void render(Window wnd, const(mat3x3d)* mat)
	{
		mat3x3d tres = (*mat) * transform.global;
		state_template.transform = tres.tosf;
		sfRenderWindow_drawConvexShape(wnd.ptr, shape, &state_template);
	}
}
