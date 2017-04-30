module dsubs_client.gui.element;

import std.algorithm;
import std.math;
import std.meta;
import std.traits;

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
class GuiElement: GuiComponent
{
	protected
	{
		GuiElement _parent;
		vec2f _position = vec2f(0, 0);
		vec2f _size = vec2f(0, 0);
		float _fraction = 0.0;
		SizeType _sizeType = SizeType.GREEDY;
	}

	this(GuiManager manager)
	{
		super(manager);
		rect = sfRectangleShape_create();
	}

	GuiElement parent() { return _parent; }

	// Called by child when it has changed somehow
	void child_changed(GuiElement child) {}

	// position in tree-space
	vec2f position() { return _position; }

	GuiElement position(vec2f val)
	{
		_position = val;
		_visuals_dirty = true;
		return this;
	}

	vec2f size() { return _size; }

	GuiElement size(vec2f size)
	{
		_size = size;
		if (_sizeType == SizeType.FIXED && _parent)
			_parent.child_changed(this);
		_visuals_dirty = true;
		return this;
	}

	float fraction() { return _fraction; }

	GuiElement fraction(float val)
	{
		_fraction = val;
		if (_sizeType == SizeType.FRACT && _parent)
			_parent.child_changed(this);
		_visuals_dirty = true;
		return this;
	}

	// type of division
	SizeType sizeType() { return _sizeType; }

	GuiElement sizeType(SizeType val)
	{
		_sizeType = val;
		return this;
	}

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

	bool visible = true;

	protected
	{
		sfColor _backgroud_color = sfTransparent;
		sfColor _border_color = sfWhite;
		float _border_width = 1.0f;
		bool _visuals_dirty = true;
	}

	sfColor backgroud_color() { return _backgroud_color; }

	GuiElement backgroud_color(sfColor val)
	{
		_backgroud_color = val;
		_visuals_dirty = true;
		return this;
	}

	sfColor border_color() { return _border_color; }

	GuiElement border_color(sfColor val)
	{
		_border_color = val;
		_visuals_dirty = true;
		return this;
	}

	/// Update rendering-related parameters from state
	void update_visual()
	{
		sfRectangleShape_setPosition(rect, tosf(_position));
		sfVector2f new_size = tosf(_size);
		new_size.x -= 1; new_size.y -= 1;	// border shenanigans
		sfRectangleShape_setSize(rect, new_size);
		sfRectangleShape_setOutlineThickness(rect, _border_width);
		sfRectangleShape_setOutlineColor(rect, _border_color);
		sfRectangleShape_setFillColor(rect, _backgroud_color);
	}

	override void draw(Window wnd)
	{
		if (visible)
		{
			if (_visuals_dirty)
				update_visual();
			sfRenderWindow_drawRectangleShape(wnd.ptr, rect, null);
		}
	}
}

template isGuiElement(T)
{
	enum isGuiElement = is(T: GuiElement);
}

enum DivType
{
	HORZ,	// children are separated by vertical line
	VERT	// children are separated by horizontal line
}

/// Divider
class Div(DivType dType): GuiElement
{
	protected GuiElement[] children;

	this(Children...)(GuiManager manager, Children kids)
		if (allSatisfy!(isGuiElement, Children))
	{
		super(manager);
		children = [kids];
		foreach (kid; children)
			kid._parent = this;
		update_children();
	}

	// type of division
	immutable DivType divType = dType;

	override vec2f position() { return _position; }

	override Div!dType position(vec2f val)
	{
		super.position(val);
		update_children();
		return this;
	}

	override vec2f size() { return _size; }

	override Div!dType size(vec2f val)
	{
		super.size(val);
		update_children();
		return this;
	}

	static if (dType == DivType.HORZ)
	{
		enum dim = 0;
		enum odim = 1;
	}
	else
	{
		enum dim = 1;
		enum odim = 0;
	}

	// anti-recusrion flag.
	protected bool _updating_children = true;

	override void child_changed(GuiElement child)
	{
		// kids are expected to notify us on their property changes
		if (!_updating_children)
			update_children();
	}

	static vec2f dim_vec(float dim_val, float odim_val)
	{
		vec2f res;
		res[dim] = dim_val;
		res[odim] = odim_val;
		return res;
	}

	// recalculate child dimensions
	protected void update_children()
	{
		_updating_children = true;
		float budget = _size[dim];
		// fixed-sized kids
		int child_count = 0;
		foreach (child; children.filter!(a => a.sizeType == SizeType.FIXED))
		{
			float child_size = chip(budget, child.size[dim]);
			budget -= child_size;
			child.size(dim_vec(child.size[dim], _size[odim]));
			child_count++;
		}
		// now fractual kids
		auto fract_kids = children.filter!(a => a.sizeType == SizeType.FRACT);
		float fract_sum = fold!((a, b) => a + b.fraction)(fract_kids, 0.0);
		fract_sum = fmax(1.0, fract_sum);
		float budget_save =  budget;
		foreach (child; fract_kids)
		{
			float new_size = child.fraction / fract_sum * budget_save;
			child.size(dim_vec(new_size, _size[odim]));
			budget -= new_size;
			child_count++;
		}
		// and now greedy ones
		int greedy_count = children.length - child_count;
		foreach (child; children.filter!(a => a.sizeType == SizeType.GREEDY))
		{
			float new_size = chip(budget, budget / greedy_count);
			child.size(dim_vec(new_size, _size[odim]));
		}
		// all offsets now are calcuated, we can set positions and sizes
		float offset = 0.0;
		foreach (child; children)
		{
			child.position(dim_vec(_position[dim] + offset, _position[odim]));
			offset += child.size[dim];
		}
		_updating_children = false;
	}

	protected float chip(float budget, float desired_val)
	{
		return fmin(fmax(0.0, budget), fmax(0.0, desired_val));
	}

	override void draw(Window wnd)
	{
		super.draw(wnd);	// container is drawn first
		foreach (child; children)
			child.draw(wnd);
	}

	override GuiElement get_from_point(vec2f point)
	{
		if (this.GuiElement.get_from_point(point))
		{
			if (children.length == 0)
				return this;
			float offset = point[dim] - _position[dim];
			float cursor = 0.0;
			foreach (kid; children)
			{
				auto check = kid.get_from_point(point);
				if (check)
					return check;
				cursor += kid.size[dim];
				if (cursor > offset)
					return this;
			}
			return this;
		}
		else
			return null;
	}
}

alias HDiv = Div!(DivType.HORZ);
alias VDiv = Div!(DivType.VERT);

unittest
{
	loadSfmlLibraries();
	auto mgr = new GuiManager();
	auto frame =
		new HDiv(mgr,
			new HDiv(mgr).sizeType(SizeType.FIXED).size(vec2f(400, 0)),
			new VDiv(mgr).sizeType(SizeType.FRACT).fraction(0.5),
			new HDiv(mgr)
		).size(vec2f(640, 480));
	assert(fabs(frame.children[0].size.x - 400.0) < 1e-6);
	assert(fabs(frame.children[1].size.x - 120.0) < 1e-6);
	assert(fabs(frame.children[2].size.x - 120.0) < 1e-6);
	assert(fabs(frame.children[0].size.y - 480.0) < 1e-6);
	assert(fabs(frame.children[1].size.y - 480.0) < 1e-6);
	assert(fabs(frame.children[2].size.y - 480.0) < 1e-6);
	assert(frame.get_from_point(vec2f(100.0, 50.0)) is frame.children[0]);
	assert(frame.get_from_point(vec2f(410.0, 300.0)) is frame.children[1]);
	assert(frame.get_from_point(vec2f(635.999, 300.0)) is frame.children[2]);
	assert(frame.get_from_point(vec2f(640.0, 400.0)) is null);
}
