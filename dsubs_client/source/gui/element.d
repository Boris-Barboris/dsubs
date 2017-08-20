module dsubs_client.gui.element;

import std.algorithm;
import std.experimental.logger;
import std.math;

public import gfm.math.vector;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

import dsubs_client.core.event;
import dsubs_client.lib.sfml;		// for conversions
import dsubs_client.core.window;
public import dsubs_client.core.utils;
import dsubs_client.input.router;
import dsubs_client.gui.manager;


// Size types sorted in priority order. Same-type elements are treated
// equally by div. SizeType is used by layouts (for example, Div) when
// calculating element sizes.
enum SizeType
{
	FIXED,		// element has fixed size
	FRACT,		// element takes fraction of space, left after FIXED elements
	CONTENT,	// element size is dictated by it's content (textbox)
	GREEDY,		// element tries to fill all available space in the container
}

/// GUI tree element. This is not an abstract class, just an empty rectangle.
class GuiElement: IInputReciever
{
	protected
	{
		// layout parameters
		vec2i _position = vec2i(0, 0);	// absolute position
		vec2i _size = vec2i(0, 0);		// size
		float _fraction = 0.0;	// if _sizeType is FRACT, this is the fraction to use
		SizeType _sizeType = SizeType.GREEDY;
		bool _hidden = false;
		// layout director
		GuiElement _parent;
	}

	this()
	{
		rect = sfRectangleShape_create();
		sfRectangleShape_setOutlineThickness(rect, 0.0f);
		backgroud_color(sfTransparent);
	}

	~this()
	{
		dispose();
	}

	void dispose()
	{
		if (rect)
			sfRectangleShape_destroy(rect);
		rect = null;
	}

	GuiElement parent() { return _parent; }

	// Called by child when it's layout-related parameters have changed
	package void child_changed(GuiElement child) {}

	mixin ElementAccessor!(GuiElement, bool, "hidden",
		"handle_hidden_set();");

	// When we are disabled or enabled, we need to notify parent
	protected void handle_hidden_set()
	{
		if (_hidden)
		{
			// return all focuses we hold
			returnKbFocus();
			returnMouseFocus();
		}
		if (_parent)
			_parent.child_changed(this);
	}

	mixin ElementAccessor!(GuiElement, vec2i, "position",
		"position_dirty = true;");

	mixin ElementAccessor!(GuiElement, vec2i, "size",
		"if ((_sizeType == SizeType.FIXED || _sizeType == SizeType.CONTENT) && _parent)
			_parent.child_changed(this);
		size_dirty = true;");

	mixin ElementAccessor!(GuiElement, float, "fraction",
		"if (_sizeType == SizeType.FRACT && _parent)
			_parent.child_changed(this);");

	mixin ElementAccessor!(GuiElement, SizeType, "sizeType",
		"if (_parent) { _parent.child_changed(this); }");

	//
	// rendering-related stuff
	//

	protected
	{
		sfRectangleShape* rect;
	}

	protected
	{
		bool _rect_visible = true;
		sfColor _backgroud_color = sfTransparent;
		bool position_dirty = true;
		bool size_dirty = true;
	}

	mixin ElementAccessor!(GuiElement, sfColor, "backgroud_color",
		"sfRectangleShape_setFillColor(rect, _backgroud_color);");

	mixin ElementAccessor!(GuiElement, bool, "rect_visible", "");

	protected void update_position()
	{
		sfRectangleShape_setPosition(rect, sfVector2f(_position.x, _position.y));
	}

	protected void update_size()
	{
		sfRectangleShape_setSize(rect, sfVector2f(_size.x, _size.y));
	}

	// return intersection between rhs and this element's rectangle
	vec4i clamp_viewport(const ref vec4i rhs)
	{
		vec4i res;
		res[0] = min(max(rhs[0], _position.x), _position.x + _size.x);
		res[1] = min(max(rhs[1], _position.y), _position.y + _size.y);
		res[2] = min(rhs[2], max(0, _position.x + _size.x - res[0]));
		res[3] = min(rhs[3], max(0, _position.y + _size.y - res[1]));
		return res;
	}

	protected void do_draw(Window wnd, const ref vec4i viewport)
	{
		sfRenderWindow_setScissor(wnd.ptr, clamp_viewport(viewport));
		draw_background_rect(wnd);
	}

	protected void draw_background_rect(Window wnd)
	{
		if (_rect_visible)
			sfRenderWindow_drawRectangleShape(wnd.ptr, rect, null);
	}

	protected void update_visuals()
	{
		if (position_dirty)
		{
			position_dirty = false;
			update_position();
		}
		if (size_dirty)
		{
			size_dirty = false;
			update_size();
		}
	}

	void draw(Window wnd, vec4i viewport)
	{
		if (!_hidden)
		{
			update_visuals();
			do_draw(wnd, viewport);
		}
	}

	//
	// Event handling
	//

	//
	// IInputReciever interface
	//

	void handleMouseEnter()
	{
		onMouseEnter(this);
	}

	void handleMouseLeave()
	{
		onMouseLeave(this);
	}

	// Example implementation
	HandleResult handleKeyboard(const sfEvent* evt)
	{
		if (!this.active)
		{
			returnKbFocus();
			return HandleResult(true);
		}
		switch (evt.type)
		{
			case (sfEvtKeyPressed):
				onKeyPressed(this, cast(const sfKeyEvent*) evt);
				break;
			case (sfEvtKeyReleased):
				onKeyReleased(this, cast(const sfKeyEvent*) evt);
				break;
			case (sfEvtTextEntered):
				onTextEntered(this, cast(const sfTextEvent*) evt);
				break;
			default:
				assert(0, "can't handle non-keyboard event here");
		}
		return HandleResult(false);
	}

	void handleMousePos(const sfEvent* evt, int x, int y,
		sfMouseButton btn, int delta)
	{
		if (btn >= 0)
		{
			if (evt.type == sfEvtMouseButtonPressed)
				onMouseDown(this, x, y, btn);
			if (evt.type == sfEvtMouseButtonReleased)
				onMouseUp(this, x, y, btn);
		}
		else if (delta != 0)
			onMouseScroll(this, x, y, delta);
		else
			onMouseMove(this, x, y);
	}

	// focuses
	protected bool kb_focused = false;
	void handleKbFocusGain() { kb_focused = true; }
	void handleKbFocusLoss() { kb_focused = false; }
	protected bool mouse_focused = false;
	void handleMouseFocusGain() { mouse_focused = true; }
	void handleMouseFocusLoss() { mouse_focused = false; }

	// focus manipulation methods

	void requestKbFocus()
	{
		Router.kbFocus(this);
	}

	void returnKbFocus()
	{
		if (kb_focused)
			Router.kbFocus(null);
	}

	void requestMouseFocus()
	{
		Router.mouseFocus(this);
	}

	void returnMouseFocus()
	{
		if (mouse_focused)
			Router.mouseFocus(null);
	}

	//
	// GUI-manager specifics
	//

	/// Return deepest GuiElement that contains the point, null otherwise.
	GuiElement get_from_point(vec2f point)
	{
		if (!this.active)
			return null;
		if ((point.x >= position.x && point.x < position.x + size.x) &&
			(point.y >= position.y && point.y < position.y + size.y))
			return this;
		else
			return null;
	}

	/// whether the element is transparent for mouse events
	bool mouse_transparent = true;

	GuiRouteResult routeMousePos(const sfEvent* evt, int x, int y)
	{
		GuiElement interceptor = get_from_point(vec2f(x, y));
		if (interceptor is this)
			return GuiRouteResult(this, mouse_transparent);
		else if (interceptor)
			return interceptor.routeMousePos(evt, x, y);
		return GuiRouteResult(null, true);
	}

	package void handleWindowResize(const sfSizeEvent* evt)
	{
		_view_dirty = true;
	}

	// events for users to subscribe to
	Event!(void delegate(GuiElement sender)) onMouseEnter;
	Event!(void delegate(GuiElement sender)) onMouseLeave;
	Event!(void delegate(GuiElement sender, int x, int y)) onMouseMove;
	Event!(void delegate(GuiElement sender, int x, int y, sfMouseButton btn)) onMouseDown;
	Event!(void delegate(GuiElement sender, int x, int y, sfMouseButton btn)) onMouseUp;
	Event!(void delegate(GuiElement sender, int x, int y, int delta)) onMouseScroll;
	Event!(void delegate(GuiElement sender, const sfKeyEvent* evt)) onKeyPressed;
	Event!(void delegate(GuiElement sender, const sfKeyEvent* evt)) onKeyReleased;
	Event!(void delegate(GuiElement sender, const sfTextEvent* evt)) onTextEntered;
}

template isGuiElement(T)
{
	enum isGuiElement = is(T: GuiElement);
}
