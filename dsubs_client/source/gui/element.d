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
	CONTENT,	// element size is dictated by it's content (textbox)
	FRACT,		// element takes fraction of space, left after FIXED elements
	GREEDY,		// element tries to fill all available space in the container
}

enum Dim: ubyte
{
	X = 0,	// horizontal
	Y = 1,	// vertical
}

/// GUI tree element. This is not an abstract class, just an empty rectangle.
class GuiElement: IInputReciever
{
	protected
	{
		// layout parameters
		vec2i _position = vec2i(0, 0);	// absolute position on the window
		vec2i _size = vec2i(0, 0);		// absolute size

		// parent viewport.
		// If null, no intersection is performed.
		// We use it separately instead of simply consulting parent
		// element's viewport as a means of optimisation. Only
		// scrollbar is actually setting it atm.
		vec4i* _parent_viewport = null;
		vec4i _viewport;	// cached viewport rectangle itself

		// if _sizeType is FRACT, this is the fraction to use
		float _fraction = 0.0;
		SizeType _sizeType = SizeType.GREEDY;
	}

	package GuiElement _parent;		// layout director of this element.

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

	protected void dispose()
	{
		if (rect)
			sfRectangleShape_destroy(rect);
		rect = null;
	}

	GuiElement parent() { return _parent; }

	// Called by child when it's layout-related parameters have changed
	package void child_changed(GuiElement child) {}

	mixin ElementAccessor!(GuiElement, vec2i, "position",
		"position_dirty = true;");

	mixin ElementAccessor!(GuiElement, vec2i, "size",
		"if ((_sizeType == SizeType.FIXED || _sizeType == SizeType.CONTENT) && _parent)
			_parent.child_changed(this);
		size_dirty = true;");

	mixin ElementAccessor!(GuiElement, vec4i*, "parent_viewport",
		"viewport_dirty = true;");

	mixin ElementAccessor!(GuiElement, float, "fraction",
		"if (_sizeType == SizeType.FRACT && _parent)
			_parent.child_changed(this);");

	mixin ElementAccessor!(GuiElement, SizeType, "sizeType",
		"if (_parent) { _parent.child_changed(this); }");

	// Called by layout manager when he sets fix_dim to a-priori known
	// size fix_dim_size, but needs to know the length required to
	// fir this element's content. This function kills two birds:
	// applies fixed dimension and content-sized one, reporting the result.
	int fit_content(Dim fix_dim, int fix_dim_size)
	{
		assert(_sizeType == SizeType.CONTENT);
		uint content_dim = fix_dim ^ 1;	// xor 1 flips the bit
		_size[fix_dim] = fix_dim_size;
		do_fit_content(content_dim);
		size_dirty = true;
		return _size[content_dim];
	}

	protected void do_fit_content(Dim content_dim)
	{
		_size[content_dim] = 0;
	}

	//
	// rendering stuff
	//

	protected
	{
		sfRectangleShape* rect;
		bool _rect_visible = true;
		sfColor _backgroud_color = sfTransparent;

		// dirty flags, that force lazy sfml state updates during rendering
		// run.
		bool position_dirty = true;
		bool size_dirty = true;
		bool viewport_dirty = true;
	}

	mixin ElementAccessor!(GuiElement, sfColor, "backgroud_color",
		"sfRectangleShape_setFillColor(rect, _backgroud_color);");

	mixin ElementAccessor!(GuiElement, bool, "rect_visible", "");

	// functions that lazily update sfml state

	protected void update_position()
	{
		sfRectangleShape_setPosition(rect, tosf(_position));
	}

	protected void update_size()
	{
		sfRectangleShape_setSize(rect, tosf(_size));
	}

	protected void update_viewport()
	{
		if (_parent_viewport)
			viewport = clamp_viewport(*_parent_viewport);
		else
			viewport = vec4i(_position.x, _position.y, _size.x, _size.y);
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

	protected void do_draw(Window wnd)
	{
		sfRenderWindow_setScissor(wnd.ptr, tosf(viewport));
		if (_rect_visible)
			sfRenderWindow_drawRectangleShape(wnd.ptr, rect, null);
	}

	protected void update_visuals()
	{
		if (position_dirty)
		{
			position_dirty = false;
			viewport_dirty = true;
			update_position();
		}
		if (size_dirty)
		{
			size_dirty = false;
			viewport_dirty = true;
			update_size();
		}
		if (viewport_dirty)
		{
			viewport_dirty = false;
			update_viewport();
		}
	}

	void draw(Window wnd)
	{
		update_visuals();
		do_draw(wnd);
	}

	//
	// Event handling
	//

	//
	// IInputReciever interface
	//

	// Example implementation
	HandleResult handleKeyboard(const sfEvent* evt)
	{
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

	void handleMouseEnter()
	{
		onMouseEnter(this);
	}

	void handleMouseLeave()
	{
		onMouseLeave(this);
	}

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
	GuiElement get_from_point(vec2i point)
	{
		if ((point.x >= position.x && point.x < position.x + size.x) &&
			(point.y >= position.y && point.y < position.y + size.y))
			return this;
		return null;
	}

	/// whether the element is transparent for mouse events
	bool mouse_transparent = true;

	// gui manager will query panels and seek first non-mouse-transparent
	// element wich is placed under cursor.
	GuiRouteResult routeMousePos(const sfEvent* evt, int x, int y)
	{
		GuiElement interceptor = get_from_point(vec2i(x, y));
		if (interceptor)
			if (mouse_transparent)
				return interceptor.routeMousePos(evt, x, y);
			else
				return GuiRouteResult(this, false);
		return GuiRouteResult(null, true);
	}

	// events for users to subscribe to
	Event!(GuiElement sender) onMouseEnter;
	Event!(GuiElement sender) onMouseLeave;
	Event!(GuiElement sender, int x, int y) onMouseMove;
	Event!(GuiElement sender, int x, int y, sfMouseButton btn) onMouseDown;
	Event!(GuiElement sender, int x, int y, sfMouseButton btn) onMouseUp;
	Event!(GuiElement sender, int x, int y, int delta) onMouseScroll;
	Event!(GuiElement sender, const sfKeyEvent* evt) onKeyPressed;
	Event!(GuiElement sender, const sfKeyEvent* evt) onKeyReleased;
	Event!(GuiElement sender, const sfTextEvent* evt) onTextEntered;
}

template isGuiElement(T)
{
	enum isGuiElement = is(T: GuiElement);
}
