module dsubs_client.gui.element;

import std.algorithm;
import std.math;
import std.meta;
import std.traits;

public import gfm.math.vector;


// Size types sorted in priority order. Same-type elements are treated
// equally
enum SizeType
{
	FIXED,	// element has fixed size
	FRACT,	// element takes fraction of free space, left after FIXED elements
	GREEDY	// element tries to fill all available space.
}

/// GUI tree element
class GuiElement
{
	protected
	{
		GuiElement _parent;
		vec2d _position = vec2d(0, 0);
		vec2d _size = vec2d(0, 0);
		double _fraction = 0.0;
		SizeType _sizeType;
	}

	this()
	{
		_sizeType = SizeType.GREEDY;
	}

	this(SizeType st, vec2d size)
	{
		_sizeType = st;
		_size = size;
	}

	@property GuiElement parent() { return _parent; }

	// position in tree-space
	@property vec2d position() { return _position; }

	@property vec2d size() { return _size; }

	@property double fraction() { return _fraction; }

	// type of division
	@property SizeType sizeType() { return _sizeType; }

	/// Return deepest GuiElement that contains the point, null otherwise.
	GuiElement get_from_point(vec2d point)
	{
		if ((point.x >= position.x && point.x < position.x + size.x) &&
			(point.y >= position.y && point.y < position.y + size.y))
			return this;
		else
			return null;
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

	this(Children...)(SizeType st, vec2d size, Children kids)
		if (allSatisfy!(isGuiElement, Children))
	{
		super(st, size);
		children = [kids];
		foreach (kid; children)
			kid._parent = this;
		update_children();
	}

	this(Children...)(vec2d size, Children kids)
		if (allSatisfy!(isGuiElement, Children))
	{
		super(SizeType.FIXED, size);
		children = [kids];
		foreach (kid; children)
			kid._parent = this;
		update_children();
	}

	this(Children...)(double fraction, Children kids)
		if (allSatisfy!(isGuiElement, Children))
	{
		_sizeType = SizeType.FRACT;
		_fraction = fraction;
		children = [kids];
		foreach (kid; children)
			kid._parent = this;
		update_children();
	}

	this(Children...)(Children kids)
		if (allSatisfy!(isGuiElement, Children))
	{
		_sizeType = SizeType.GREEDY;
		children = [kids];
		foreach (kid; children)
			kid._parent = this;
		update_children();
	}

	// type of division
	@property DivType divType() { return dType; }

	override @property vec2d size() { return _size; }

	@property vec2d size(vec2d val)
	{
		_size = val;
		update_children();
		return _size;
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

	// recalculate child dimensions
	protected void update_children()
	{
		double budget = size[dim];
		// fixed-sized kids
		int child_count = 0;
		foreach (child; children.filter!(a => a.sizeType == SizeType.FIXED))
		{
			double new_size = chip(budget, child.size[dim]);
			budget -= new_size;
			child._size[dim] = new_size;
			child_count++;
		}
		// now fractual kids
		auto fract_kids = children.filter!(a => a.sizeType == SizeType.FRACT);
		double fract_sum = fold!((a, b) => a + b.fraction)(fract_kids, 0.0);
		fract_sum = fmax(1.0, fract_sum);
		double budget_save =  budget;
		foreach (child; fract_kids)
		{
			double new_size = child.fraction / fract_sum * budget_save;
			child._size[dim] = new_size;
			budget -= new_size;
			child_count++;
		}
		// and now greedy ones
		int greedy_count = children.length - child_count;
		foreach (child; children.filter!(a => a.sizeType == SizeType.GREEDY))
		{
			child._size[dim] = chip(budget, budget / greedy_count);
		}
		// all offsets now are calcuated, we can set positions and sizes
		double offset = 0.0;
		foreach (child; children)
		{
			child._position[dim] = position[dim] + offset;
			child._position[odim] = position[odim];
			child._size[odim] = size[odim];
			offset += child.size[dim];
		}
	}

	protected double chip(double budget, double desired_val)
	{
		return fmin(fmax(0.0, budget), fmax(0.0, desired_val));
	}

	override GuiElement get_from_point(vec2d point)
	{
		if (this.GuiElement.get_from_point(point))
		{
			if (children.length == 0)
				return this;
			double offset = point[dim] - position[dim];
			double cursor = 0.0;
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
	auto frame =
		new HDiv(vec2d(640, 480),
			new HDiv(vec2d(400, 0)),
			new VDiv(0.5),
			new HDiv());
	assert(fabs(frame.children[0].size.x - 400.0) < 1e-6);
	assert(fabs(frame.children[1].size.x - 120.0) < 1e-6);
	assert(fabs(frame.children[2].size.x - 120.0) < 1e-6);
	assert(fabs(frame.children[0].size.y - 480.0) < 1e-6);
	assert(fabs(frame.children[1].size.y - 480.0) < 1e-6);
	assert(fabs(frame.children[2].size.y - 480.0) < 1e-6);
	assert(frame.get_from_point(vec2d(100.0, 50.0)) is frame.children[0]);
	assert(frame.get_from_point(vec2d(410.0, 300.0)) is frame.children[1]);
	assert(frame.get_from_point(vec2d(635.999, 300.0)) is frame.children[2]);
	assert(frame.get_from_point(vec2d(640.0, 400.0)) is null);
}
