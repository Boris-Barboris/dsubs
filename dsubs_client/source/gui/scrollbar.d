module dsubs_client.gui.scrollbar;

import std.algorithm.comparison: min, max;
import std.conv: to;
import std.experimental.logger;
import std.math;

public import gfm.math.vector;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

import dsubs_client.core.window;
public import dsubs_client.gui.element;
import dsubs_client.gui.fonts;
import dsubs_client.gui.manager;


class ScrollBar: GuiElement
{
	__gshared float SCROLL_SPEED = 25.0f;

	protected
	{
		float _scroll_position = 0.0f;
		GuiElement _child;
	}

	GuiElement child() { return _child; }

	this(GuiManager manager, GuiElement child)
	{
		assert(child !is null);
		super(manager);
		mouse_transparent = false;
		_child = child;
		_child._parent = this;
		_child.border_color(sfTransparent);
		_child.border_width(0);
		update_child();
		onMouseScroll += &handle_mouse_scroll;
	}

	mixin SuperAccessor!(ScrollBar, vec2f, "position", "update_child();");

	mixin SuperAccessor!(ScrollBar, vec2f, "size", "update_child();");

	mixin SuperAccessor!(ScrollBar, vec4f, "viewport", "update_child();");

	protected void update_child()
	{
		_child.size(vec2f(_size.x, _size.y));
		//update_mouse_scroll(0);
		//_child.size(vec2f(_size.x, _size.y));
		vec2f new_child_pos =
			vec2f(this._position.x, this._position.y + _scroll_position);
		_child.viewport(
			clamp_viewport(
				vec4f(_position.x, _position.y,
					  _size.x, _size.y)));
		_child.position(new_child_pos);
	}

	private void handle_mouse_scroll(GuiElement sender, int x, int y, int delta)
	{
		update_mouse_scroll(delta);
		update_child();
	}

	protected void update_mouse_scroll(int delta)
	{
		float max_scroll = (_child.content_size.y - _size.y + 2.0f * _border_width);
		if (max_scroll <= 0.0f)
			_scroll_position = 0.0f;
		else
		{
			_scroll_position += ScrollBar.SCROLL_SPEED * delta;
			_scroll_position = fmin(0.0f, fmax(_scroll_position, -max_scroll));
		}
	}

	override void draw(Window wnd)
	{
		super.draw(wnd);
		if (_child.active)
			_child.draw(wnd);
	}
}

ScrollBar asScrollBar(GuiElement el)
{
	return cast(ScrollBar) el;
}
