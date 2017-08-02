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
	GREEDY,	// element tries to fill all available space in the container.
	CONTENT,// element controlls it's own size
}

/// GUI tree element. This is not an abstract class, just an empty rectangle.
class GuiElement: Component!"Gui", IInputReciever
{
	package GuiElement _parent;
	protected
	{
		vec2f _position = vec2f(0, 0);	// absolute position
		vec2f _size = vec2f(0, 0);		// size
		vec2f _content_size = vec2f(0, 0);
		// rectangle to view this element through: x,y,w,h
		vec4f _viewport = vec4f(0, 0, 0, 0);
		float _fraction = 0.0;			// if _sizeType is FRACT, this is the fraction to use
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
		if (!active)
		{
			// return all focuses we hold
			returnKbFocus();
			returnMouseFocus();
		}
		if (_parent)
			_parent.child_changed(this);
	}

	mixin ElementAccessor!(GuiElement, vec2f, "position",
		"_view_dirty = true;");

	mixin ElementAccessor!(GuiElement, vec4f, "viewport",
		"_view_dirty = true;");

	mixin ElementAccessor!(GuiElement, vec2f, "size",
		"if ((_sizeType == SizeType.FIXED || _sizeType == SizeType.CONTENT) && _parent)
			_parent.child_changed(this);
		_visuals_dirty = _view_dirty = true;");

	mixin ElementAccessor!(GuiElement, float, "fraction",
		"if (_sizeType == SizeType.FRACT && _parent)
			_parent.child_changed(this);");

	mixin ElementAccessor!(GuiElement, SizeType, "sizeType",
		"if (_parent) { _parent.child_changed(this); }");

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
		bool _rect_visible = true;	// is layout rectangle visible?
		sfColor _backgroud_color = sfTransparent;
		sfColor _border_color = sfColor(255, 255, 255, 30);
		uint _border_width = 1;		// width of layout rectangle border
		bool _visuals_dirty = true;	// when true, content must be recalculated
		bool _view_dirty = true;	// when true, view must be recalcuated
	}

	mixin ElementAccessor!(GuiElement, sfColor, "backgroud_color",
		"sfRectangleShape_setFillColor(rect, _backgroud_color);");

	mixin ElementAccessor!(GuiElement, sfColor, "border_color",
		"sfRectangleShape_setOutlineColor(rect, _border_color);");

	mixin ElementAccessor!(GuiElement, uint, "border_width",
		"_visuals_dirty = true;");

	mixin ElementAccessor!(GuiElement, bool, "rect_visible", "");

	/// Update rendering-related parameters from state
	protected void update_visual()
	{
		sfRectangleShape_setPosition(rect, sfVector2f(_border_width, _border_width));
		sfVector2f new_size = tosf(_size - 2.0f * vec2f(_border_width, _border_width));
		new_size.x = round(new_size.x); new_size.y = round(new_size.y);
		sfRectangleShape_setSize(rect, new_size);
		sfRectangleShape_setOutlineThickness(rect, _border_width);
		sfRectangleShape_setOutlineColor(rect, _border_color);
		sfRectangleShape_setFillColor(rect, _backgroud_color);
	}

	// return rectangle rhs clamped inside this element's viewport
	vec4f clamp_viewport(vec4f rhs)
	{
		vec4f res;
		res[0] = min(max(rhs[0], _viewport[0]), _viewport[0] + _viewport[2]);
		res[1] = min(max(rhs[1], _viewport[1]), _viewport[1] + _viewport[3]);
		res[2] = min(rhs[2], max(0.0f, _viewport[0] + _viewport[2] - res[0]));
		res[3] = min(rhs[3], max(0.0f, _viewport[1] + _viewport[3] - res[1]));
		return res;
	}

	protected void update_view(Window wnd)
	{
		// set camera coordinates of the view
		sfFloatRect coord;
		coord.left = round(_viewport.x - _position.x);
		coord.top = round(_viewport.y - _position.y);
		coord.width = round(_viewport[2]);
		coord.height = round(_viewport[3]);
		sfView_reset(view, coord);
		// update viewport
		sfFloatRect vp;
		vp.left = round(_viewport.x) / wnd.width;
		vp.top = round(_viewport.y) / wnd.height;
		vp.width = coord.width / wnd.width;
		vp.height = coord.height / wnd.height;
		sfView_setViewport(view, vp);
	}

	protected void set_view(Window wnd)
	{
		sfRenderWindow_setView(wnd.ptr, view);
	}

	protected void reset_view(Window wnd)
	{
		sfRenderWindow_setView(wnd.ptr, wnd.view);
	}

	protected void do_draw(Window wnd)
	{
		draw_background_rect(wnd);
	}

	protected void draw_background_rect(Window wnd)
	{
		if (_rect_visible)
			sfRenderWindow_drawRectangleShape(wnd.ptr, rect, null);
	}

	void draw(Window wnd)
	{
		if (_view_dirty)
			update_view(wnd);
		_view_dirty = false;
		if (_visuals_dirty)
			update_visual();
		_visuals_dirty = false;
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
