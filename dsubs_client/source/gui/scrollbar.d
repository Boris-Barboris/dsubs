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
		sb_background = sfRectangleShape_create();
		sb_handle = sfRectangleShape_create();
		sfRectangleShape_setOutlineThickness(sb_handle, 0);
		sfRectangleShape_setOutlineThickness(sb_background, 1);
		sfRectangleShape_setOutlineColor(sb_background, _sb_background_border_color);
		sfRectangleShape_setFillColor(sb_background, _sb_background_fill_color);
		sfRectangleShape_setFillColor(sb_handle, _sb_handle_color);
		_child = child;
		_child._parent = this;
		_child.border_color(sfTransparent);
		_child.border_width(0);
		backgroud_color(sfTransparent);
		mouse_transparent = false;
		// only one of the two will be called during scroll event:
		_child.onMouseScroll += &handle_mouse_scroll;
		this.onMouseScroll += &handle_mouse_scroll;
		// assign handlers for scrollbar-mouse interactions
		this.onMouseDown += &handle_mouse_down;
		this.onMouseUp += &handle_mouse_up;
		this.onMouseMove += &handle_mouse_move;
	}

	// visual staff
	protected
	{
		sfRectangleShape* sb_background;	// scrollbar background rect
		sfRectangleShape* sb_handle;			// scrollbar handle rect
		uint _scrollbar_width = 10;
		uint _min_sb_handle_length = 10;
		sfColor _sb_background_border_color = sfColor(255, 255, 255, 100);
		sfColor _sb_background_fill_color = sfTransparent;
		sfColor _sb_handle_color = sfWhite;
		bool _sb_visible = true;
	}

	private
	{
		// y coordinate and size of the scrollbar handle
		float handle_length = 0.0f;
		float sb_handle_y = 0.0f;
	}

	mixin SuperAccessor!(GuiElement, vec2f, "position",
		"update_child_viewport(); update_child_position();");

	mixin SuperAccessor!(GuiElement, vec2f, "size", "_child_needs_update = true;");

	mixin SuperAccessor!(GuiElement, vec4f, "viewport", "update_child_viewport();");

	mixin ElementAccessor!(GuiElement, sfColor, "sb_background_border_color",
		"sfRectangleShape_setOutlineColor(sb_background, _sb_background_border_color);");

	mixin ElementAccessor!(GuiElement, sfColor, "sb_background_fill_color",
		"sfRectangleShape_setFillColor(sb_background, _sb_background_fill_color);");

	mixin ElementAccessor!(GuiElement, sfColor, "sb_handle_color",
		"sfRectangleShape_setFillColor(sb_handle, _sb_handle_color);");

	mixin ElementAccessor!(GuiElement, uint, "scrollbar_width",
		"_child_needs_update = true;");

	mixin ElementAccessor!(GuiElement, uint, "min_sb_handle_length", "");

	// sets up scrollbar visuals
	protected void update_sb_visual()
	{
		if (_child.size.y > 0.0f)
		{
			float frame_ratio = (_size.y - 2.0f * _border_width) / _child.size.y;
			if (frame_ratio >= 1.0f)
			{
				// child can be fit inside container and we have no need in
				// the scrollbar, let's make it transparent
				_sb_visible = false;
			}
			else
			{
				// let's calculate the handle position
				_sb_visible = true;
				handle_length = max(_min_sb_handle_length,
					frame_ratio * (_size.y - 2.0f * _border_width));
				float x = -_scroll_position / max_scroll;
				sb_handle_y = _border_width +
					x * (_size.y - 2.0f * _border_width - handle_length);
				float sb_handle_x = _size.x - _scrollbar_width - _border_width;
				sfRectangleShape_setPosition(sb_background,
					sfVector2f(sb_handle_x, _border_width));
				sfRectangleShape_setPosition(sb_handle,
					sfVector2f(sb_handle_x, sb_handle_y));
				sfRectangleShape_setSize(sb_background,
					sfVector2f(_scrollbar_width, _size.y - 2.0f * _border_width));
				sfRectangleShape_setSize(sb_handle,
					sfVector2f(_scrollbar_width, handle_length));
			}
		}
		else
			_sb_visible = false;
	}

	protected void update_child()
	{
		_child.size(vec2f(_size.x - _scrollbar_width, _child.size.y));
		// child size assignment triggers child_changed
		update_child_viewport();
		update_child_position();
	}

	protected void update_child_viewport()
	{
		_child.viewport(
			clamp_viewport(
				vec4f(_position.x, _position.y,
					  _size.x - _scrollbar_width, _size.y)));
	}

	protected void update_child_position()
	{
		vec2f new_child_pos =
			vec2f(this._position.x, this._position.y + _scroll_position);
		_child.position(new_child_pos);
		update_sb_visual();
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

	private float max_scroll;

	protected void update_mouse_scroll(int delta, float speed_gain = ScrollBar.SCROLL_SPEED)
	{
		max_scroll = (_child.size.y - _size.y + 2.0f * _border_width);
		if (max_scroll <= 0.0f)
			_scroll_position = 0.0f;
		else
		{
			_scroll_position += speed_gain * delta;
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

	protected override void do_draw(Window wnd)
	{
		super.do_draw(wnd);
		if (_sb_visible)
		{
			sfRenderWindow_drawRectangleShape(wnd.ptr, sb_background, null);
			sfRenderWindow_drawRectangleShape(wnd.ptr, sb_handle, null);
		}
	}

	override GuiElement get_from_point(vec2f point)
	{
		if (super.get_from_point(point))
		{
			// first we check if we are pointing on the scrollbar
			if (_sb_visible && point.x >= _size.x - _border_width - _scrollbar_width)
				return this;
			auto check = _child.get_from_point(point);
			if (check)
				return check;
			return this;
		}
		else
			return null;
	}

	private bool point_on_scrollbar_body(int x, int y)
	{
		float lx = x - _position.x;
		float ly = y - _position.y;
		return (_sb_visible && lx >= _size.x - _border_width - _scrollbar_width &&
			ly >= sb_handle_y && ly <= (sb_handle_y + handle_length));
	}

	private int prev_y = -1;

	private void handle_mouse_down(GuiElement sender, int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseLeft && point_on_scrollbar_body(x, y))
		{
			// user clicked on scrollbar, let's capture it
			requestMouseFocus();
			prev_y = y;
		}
	}

	private void handle_mouse_up(GuiElement sender, int x, int y, sfMouseButton btn)
	{
		if (btn == sfMouseLeft && mouse_focused)
			returnMouseFocus();
	}

	private void handle_mouse_move(GuiElement sender, int x, int y)
	{
		if (mouse_focused && _sb_visible)
		{
			int delta = y - prev_y;
			float gain = _child.size.y / _size.y;
			update_mouse_scroll(-delta, gain);
			update_child_position();
			prev_y = y;
		}
	}
}

ScrollBar!T asScrollBar(T)(GuiElement el)
{
	return cast(ScrollBar!T) el;
}
