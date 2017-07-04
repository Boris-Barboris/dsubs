module dsubs_client.gui.scrollbar;

import std.algorithm.comparison: min, max;
import std.conv: to;
import std.experimental.logger;
import std.math;
import std.traits: isAssignable;

public import gfm.math.vector;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

import dsubs_client.core.window;
public import dsubs_client.gui.element;
import dsubs_client.gui.fonts;
import dsubs_client.gui.manager;


class ScrollBar(ChildT): GuiElement
	if (is(ChildT == class) && isAssignable!(GuiElement, ChildT))
{
	__gshared float SCROLL_SPEED = 25.0f;

	protected
	{
		float _scroll_position = 0.0f;
		ChildT _child;
		bool _child_needs_update = true;
	}

	ChildT child() { return _child; }

	this(GuiManager manager, ChildT child)
	{
		assert(child !is null);
		super(manager);
		mouse_transparent = false;
		_child = child;
		_child._parent = this;
		_child.border_color(sfTransparent);
		_child.border_width(0);
		onMouseScroll += &handle_mouse_scroll;
	}

	mixin SuperAccessor!(GuiElement, vec2f, "position",
		"update_child_viewport(); update_child_position();");

	mixin SuperAccessor!(GuiElement, vec2f, "size", "_child_needs_update = true;");

	mixin SuperAccessor!(GuiElement, vec4f, "viewport", "update_child_viewport();");

	protected void update_child()
	{
		_child.size(vec2f(_size.x, _child.size.y));	// this triggers child_changed
		update_child_viewport();
		update_child_position();
	}

	protected void update_child_viewport()
	{
		_child.viewport(
			clamp_viewport(
				vec4f(_position.x, _position.y,
					  _size.x, _size.y)));
	}

	protected void update_child_position()
	{
		vec2f new_child_pos =
			vec2f(this._position.x, this._position.y + _scroll_position);
		_child.position(new_child_pos);
	}

	override void child_changed(GuiElement child)
	{
		// this ensures that _scroll_position is adequate and not out of bounds
		update_mouse_scroll(0);
		update_child_position();
	}

	private void handle_mouse_scroll(GuiElement sender, int x, int y, int delta)
	{
		update_mouse_scroll(delta);
		update_child_position();
	}

	protected void update_mouse_scroll(int delta)
	{
		float max_scroll = (_child.size.y - _size.y + 2.0f * _border_width);
		if (max_scroll <= 0.0f)
			_scroll_position = 0.0f;
		else
		{
			_scroll_position += ScrollBar.SCROLL_SPEED * delta;
			_scroll_position = fmin(0.0f, fmax(_scroll_position, -max_scroll));
		}
	}

	override protected void update_visual()
	{
		super.update_visual();
		if (_child_needs_update)
			update_child();
		_child_needs_update = false;
	}

	override void draw(Window wnd)
	{
		super.draw(wnd);
		if (_child.active)
			_child.draw(wnd);
	}
}

ScrollBar!T asScrollBar(T)(GuiElement el)
{
	return cast(ScrollBar!T) el;
}
