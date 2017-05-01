module dsubs_client.gui.element;

import std.algorithm;
import std.experimental.logger;

public import gfm.math.vector;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

import dsubs_client.core.sfml;		// for conversions
import dsubs_client.core.window;
import dsubs_client.gui.manager;


// Size types sorted in priority order. Same-type elements are treated
// equally
enum SizeType
{
	FIXED,	// element has fixed size
	FRACT,	// element takes fraction of free space, left after FIXED elements
	GREEDY	// element tries to fill all available space.
}

/// GUI tree element. This is not an abstract class, just an empty rectangle.
class GuiElement: Component!"Gui"
{
	package GuiElement _parent;		// TODO: protected
	protected
	{
		vec2f _position = vec2f(0, 0);
		vec2f _size = vec2f(0, 0);
		float _fraction = 0.0;
		SizeType _sizeType = SizeType.GREEDY;
	}

	/// Mixins to reduce boilerplate
	protected mixin template ElementAccessor(ElType, T, string field_name, string update_code)
	{
		mixin(T.stringof ~ " " ~ field_name ~ "() { return _" ~ field_name ~ ";};");
		mixin(ElType.stringof ~ " " ~ field_name ~ "(" ~ T.stringof ~ " val) " ~
			"{ _" ~ field_name ~ "=val;" ~ update_code ~ "return this;}");
	}

	protected mixin template SuperAccessor(ElType, T, string field_name, string update_code)
	{
		mixin("override " ~ T.stringof ~ " " ~ field_name ~
			"() { return _" ~ field_name ~ ";};");
		mixin("override " ~ ElType.stringof ~ " " ~ field_name ~ "(" ~ T.stringof ~ " val) " ~
			"{ super." ~ field_name ~ "(val);" ~ update_code ~ "return this;}");
	}

	this(GuiManager manager)
	{
		super(manager);
		rect = sfRectangleShape_create();
	}

	GuiElement parent() { return _parent; }

	// When we are disabled, we need to notify parent
	mixin SuperAccessor!(GuiElement, CompState, "state",
		"if (_parent) _parent.child_changed(this);");

	// Called by child when it has changed somehow
	void child_changed(GuiElement child) {}

	mixin ElementAccessor!(GuiElement, vec2f, "position",
		"_visuals_dirty = true;");

	mixin ElementAccessor!(GuiElement, vec2f, "size",
		"if (_sizeType == SizeType.FIXED && _parent)
			_parent.child_changed(this);
		_visuals_dirty = true;");

	mixin ElementAccessor!(GuiElement, float, "fraction",
		"if (_sizeType == SizeType.FRACT && _parent)
			_parent.child_changed(this);
		_visuals_dirty = true;");

	mixin ElementAccessor!(GuiElement, SizeType, "sizeType", "");

	/// Return deepest GuiElement that contains the point, null otherwise.
	GuiElement get_from_point(vec2f point)
	{
		if ((point.x >= position.x && point.x < position.x + size.x) &&
			(point.y >= position.y && point.y < position.y + size.y))
			return this;
		else
			return null;
	}

	//
	// rendering stuff
	//

	protected
	{
		sfRectangleShape* rect;
	}

	bool _visible = true;

	protected
	{
		sfColor _backgroud_color = sfTransparent;
		sfColor _border_color = sfWhite;
		float _border_width = 1.0f;
		bool _visuals_dirty = true;
	}

	mixin ElementAccessor!(GuiElement, sfColor, "backgroud_color",
		"_visuals_dirty = true;");

	mixin ElementAccessor!(GuiElement, sfColor, "border_color",
		"_visuals_dirty = true;");

	mixin ElementAccessor!(GuiElement, float, "border_width",
		"_visuals_dirty = true;");

	mixin ElementAccessor!(GuiElement, bool, "visible", "");

	/// Update rendering-related parameters from state
	void update_visual()
	{
		sfRectangleShape_setPosition(rect, tosf(_position));
		sfVector2f new_size = tosf(_size);
		sfRectangleShape_setSize(rect, new_size);
		sfRectangleShape_setOutlineThickness(rect, _border_width);
		sfRectangleShape_setOutlineColor(rect, _border_color);
		sfRectangleShape_setFillColor(rect, _backgroud_color);
	}

	void draw(Window wnd)
	{
		if (visible)
		{
			if (_visuals_dirty)
				update_visual();
			sfRenderWindow_drawRectangleShape(wnd.ptr, rect, null);
		}
	}

	// Event handling
	package GuiHandleResult handleMousePosEvent(const sfEvent* evt,
		int x, int y, sfMouseButton btn, int delta)
	{
		GuiElement interceptor = get_from_point(vec2f(x, y));
		if (interceptor == this)
		{
			if (btn >= 0)
			{
				if (evt.type == sfEvtMouseButtonPressed)
				{
					// default behaviour of unsetting focus
					GuiManager m = cast(GuiManager) _manager;
					if (m.kb_focus && (m.kb_focus != this))
						m.kb_focus = null;
					if (onMouseDown)
						onMouseDown(this, x, y, btn);
				}
				if (evt.type == sfEvtMouseButtonReleased)
					if (onMouseUp)
						onMouseUp(this, x, y, btn);
			}
			else if (delta != 0)
			{
				if (onMouseScroll)
					onMouseScroll(this, x, y, delta);
			}
			else if (onMouseMove)
			{
				onMouseMove(this, x, y);
			}
			return GuiHandleResult(true, this);
		}
		else if (interceptor)
			return interceptor.handleMousePosEvent(evt, x, y, btn, delta);
		return GuiHandleResult(true, null);
	}

	package void handleMouseEnter()
	{
		if (onMouseEnter)
			onMouseEnter(this);
	}

	package void handleMouseLeave()
	{
		if (onMouseLeave)
			onMouseLeave(this);
	}

	package GuiHandleResult handleKeyboard(const sfEvent* evt)
	{
		switch (evt.type)
		{
			case (sfEvtKeyPressed):
				if (onKeyPressed)
					onKeyPressed(this, cast(const sfKeyEvent*) evt);
				break;
			case (sfEvtKeyReleased):
				if (onKeyReleased)
					onKeyReleased(this, cast(const sfKeyEvent*) evt);
				break;
			case (sfEvtTextEntered):
				if (onTextEntered)
					onTextEntered(this, cast(const sfTextEvent*) evt);
				break;
			default: break;
		}
		return GuiHandleResult(false, this);
	}

	// events for users to subscribe to
	void delegate(GuiElement sender) onMouseEnter;
	void delegate(GuiElement sender) onMouseLeave;
	void delegate(GuiElement sender, int x, int y) onMouseMove;
	void delegate(GuiElement sender, int x, int y, sfMouseButton btn) onMouseDown;
	void delegate(GuiElement sender, int x, int y, sfMouseButton btn) onMouseUp;
	void delegate(GuiElement sender, int x, int y, int delta) onMouseScroll;
	void delegate(GuiElement sender, const sfKeyEvent* evt) onKeyPressed;
	void delegate(GuiElement sender, const sfKeyEvent* evt) onKeyReleased;
	void delegate(GuiElement sender, const sfTextEvent* evt) onTextEntered;
}

template isGuiElement(T)
{
	enum isGuiElement = is(T: GuiElement);
}
