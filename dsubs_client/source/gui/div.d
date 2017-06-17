module dsubs_client.gui.div;

import std.algorithm;
import std.experimental.logger;
import std.math;
import std.meta;

public import gfm.math.vector;

import derelict.sfml2.graphics;
import derelict.sfml2.system;
import derelict.sfml2.window;

import dsubs_client.core.sfml;		// for conversions
import dsubs_client.core.window;
public import dsubs_client.gui.element;
import dsubs_client.gui.manager;


enum DivType
{
	HORZ,	// children are separated by vertical line
	VERT	// children are separated by horizontal line
}

/// Divider
class Div(uint dim, uint odim): GuiElement
	if (dim + odim == 1)
{
	GuiElement[] children;

	this(Children...)(GuiManager manager, Children kids)
		if (allSatisfy!(isGuiElement, Children))
	{
		super(manager);
		children = [kids];
		foreach (kid; children)
			kid._parent = this;
		update_children();
	}

	static if (dim == 0)
	{
		immutable DivType divType = DivType.HORZ;
	}
	static if (dim == 1)
	{
		immutable DivType divType = DivType.VERT;
	}

	mixin SuperAccessor!(Div!(dim, odim), vec2f, "position",
		"update_children();");

	mixin SuperAccessor!(Div!(dim, odim), vec2f, "size",
		"update_children();");

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
		foreach (child; children.filter!(a => a.sizeType == SizeType.FIXED && a.active))
		{
			float child_size = chip(budget, child.size[dim]);
			budget -= child_size;
			child.size(dim_vec(child.size[dim], _size[odim]));
			child_count++;
		}
		// now fractual kids
		auto fract_kids = children.filter!(a => a.sizeType == SizeType.FRACT && a.active);
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
		foreach (child; children.filter!(a => a.sizeType == SizeType.GREEDY && a.active))
		{
			float new_size = chip(budget, budget / greedy_count);
			child.size(dim_vec(new_size, _size[odim]));
		}
		// all offsets now are calcuated, we can set positions and sizes
		float offset = 0.0;
		foreach (child; filter!(a => a.active)(children))
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
			if (child.active)
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
			int cycle = 0;
			foreach (kid; filter!(a => a.active)(children))
			{
				auto check = kid.get_from_point(point);
				if (check)
					return check;
				cursor += kid.size[dim];
				if (cursor > offset)
					return this;
				cycle++;
			}
			return this;
		}
		else
			return null;
	}
}

alias HDiv = Div!(0, 1);
alias VDiv = Div!(1, 0);

HDiv asHdiv(GuiElement el)
{
	return cast(HDiv) el;
}

VDiv asVdiv(GuiElement el)
{
	return cast(VDiv) el;
}

unittest
{
	loadSfmlLibraries();
	GuiManager mgr = null;
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
	assert(frame.get_from_point(vec2f(100.0, 50.0)) == frame.children[0]);
	assert(frame.get_from_point(vec2f(410.0, 300.0)) == frame.children[1]);
	assert(frame.get_from_point(vec2f(635.999, 300.0)) == frame.children[2]);
	assert(frame.get_from_point(vec2f(640.0, 400.0)) is null);
}
