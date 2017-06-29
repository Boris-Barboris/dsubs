module dsubs_client.gui.element;

import std.algorithm;
import std.experimental.logger;
import std.math;

public import gfm.math.vector;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

import dsubs_client.core.event;
import dsubs_client.core.sfml;		// for conversions
import dsubs_client.core.window;
public import dsubs_client.core.utils;
import dsubs_client.input.router;
import dsubs_client.gui.manager;


// Size types sorted in priority order. Same-type elements are treated
// equally
enum SizeType
{
	FIXED,	// element has fixed size
	FRACT,	// element takes fraction of free space, left after FIXED elements
	GREEDY	// element tries to fill all available space in the container.
}

/// GUI tree element. This is not an abstract class, just an empty rectangle.
class GuiElement: Component!"Gui", IInputReciever
{
	package GuiElement _parent;
	protected
	{
		vec2f _position = vec2f(0, 0);
		vec2f _size = vec2f(0, 0);
		float _fraction = 0.0;
		SizeType _sizeType = SizeType.GREEDY;
	}

	this(GuiManager manager)
	{
		super(manager);
		rect = sfRectangleShape_create();
		view = sfView_create();
	}

	GuiManager manager() { return cast(GuiManager) _manager; }

	GuiElement parent() { return _parent; }

	// Called by child when it has changed somehow
	void child_changed(GuiElement child) {}

	// When we are disabled or enabled, we need to notify parent
	override void on_state_change()
	{
		if (_parent) _parent.child_changed(this);
	}

	mixin ElementAccessor!(GuiElement, vec2f, "position", "");

	mixin ElementAccessor!(GuiElement, vec2f, "size",
		"if (_sizeType == SizeType.FIXED && _parent)
			_parent.child_changed(this);
		_visuals_dirty = true;");

	mixin ElementAccessor!(GuiElement, float, "fraction",
		"if (_sizeType == SizeType.FRACT && _parent)
			_parent.child_changed(this);
		_visuals_dirty = true;");

	mixin ElementAccessor!(GuiElement, SizeType, "sizeType", "");

	//
	// rendering stuff
	//

	protected
	{
		sfRectangleShape* rect;
		sfView* view;
	}

	protected
	{
		bool _rect_visible = true;
		sfColor _backgroud_color = sfTransparent;
		sfColor _border_color = sfWhite;
		float _border_width = 0.25f;
		bool _visuals_dirty = true;
	}

	mixin ElementAccessor!(GuiElement, sfColor, "backgroud_color",
		"_visuals_dirty = true;");

	mixin ElementAccessor!(GuiElement, sfColor, "border_color",
		"_visuals_dirty = true;");

	mixin ElementAccessor!(GuiElement, float, "border_width",
		"_visuals_dirty = true;");

	mixin ElementAccessor!(GuiElement, bool, "rect_visible", "");

	/// Update rendering-related parameters from state
	void update_visual(Window wnd)
	{
		// set coordinates of the view
		sfFloatRect coord;
		coord.left = 0.0f;
		coord.top = 0.0f;
		coord.width = _size.x;
		coord.height = _size.y;
		sfView_reset(view, coord);
		//sfRectangleShape_setPosition(rect, tosf(_position));
		sfRectangleShape_setPosition(rect, sfVector2f(_border_width, _border_width));
		sfVector2f new_size = tosf(_size - 2.0f * vec2f(_border_width, _border_width));
		sfRectangleShape_setSize(rect, new_size);
		sfRectangleShape_setOutlineThickness(rect, _border_width);
		sfRectangleShape_setOutlineColor(rect, _border_color);
		sfRectangleShape_setFillColor(rect, _backgroud_color);
	}

	void update_viewport(Window wnd)
	{
		sfFloatRect vp;
		vp.left = _position.x / wnd.width;
		vp.top = _position.y / wnd.height;
		vp.width = _size.x / wnd.width;
		vp.height = _size.y / wnd.height;
		sfView_setViewport(view, vp);
	}

	void set_view(Window wnd)
	{
		sfRenderWindow_setView(wnd.ptr, view);
	}

	void reset_view(Window wnd)
	{
		sfRenderWindow_setView(wnd.ptr, wnd.view);
	}

	void do_draw(Window wnd)
	{
		if (_rect_visible)
			sfRenderWindow_drawRectangleShape(wnd.ptr, rect, null);
	}

	void draw(Window wnd)
	{
		if (_visuals_dirty)
			update_visual(wnd);
		_visuals_dirty = false;
		update_viewport(wnd);
		set_view(wnd);
		do_draw(wnd);
		reset_view(wnd);
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
				throw new Exception("can't handle non-keyboard event here");
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

	package GuiRouteResult routeMousePos(const sfEvent* evt, int x, int y)
	{
		GuiElement interceptor = get_from_point(vec2f(x, y));
		if (interceptor is this)
			return GuiRouteResult(this, mouse_transparent);
		else if (interceptor)
			return interceptor.routeMousePos(evt, x, y);
		return GuiRouteResult(null, true);
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
