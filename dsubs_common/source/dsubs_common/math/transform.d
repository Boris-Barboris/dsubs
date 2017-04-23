module dsubs_common.math.transform;

import std.algorithm;
import std.container : DList;
public import std.math;
import std.range;

public import gfm.math.matrix;
public import gfm.math.vector;


// Returns a - b, clamped to [-PI_2; PI_2]
double angleDist(double a, double b)
{
	double val = fmod(a - b, PI);
	if (abs(val) > PI_2)
		val -= sgn(val) * PI;
	return val;
}

// Hierarchical transform.
// Dsubs world is a 2D space. World X axis is directed to
// the right, Y axis - up. Positive angle is counter-clockwise. Zero rotation
// angle is aligned with Y axis - 0 rotation is directed to the North.
class Transform2D
{
	protected
	{
		// Individual components
		vec2d _scale;
		double _rotation;		// radians
		vec2d _translation;
		// Resulting transformations
		mat3x3d local_transform;
		mat3x3d world_cache;	// cached value of world-coordinates transform
		Transform2D _parent;
		DList!Transform2D _children;
	}

	this()
	{
		from_components(vec2d(1.0, 1.0), 0.0, vec2d(0.0, 0.0));
	}

	/// Propagate parent's world transform to curren one
	protected void propagate()
	{
		// multiply parent's world_cache onto local_transform and save the
		// result as current transform world_cache.
		if (_parent)
			world_cache = _parent.world_cache * local_transform;
		else
			world_cache = local_transform;
		update_children();
	}

	// Force child transforms to recalculate their matrixes
	protected void update_children()
	{
		foreach (t; _children)
			t.propagate();
	}

	void add_child(Transform2D child)
	{
		_children ~= child;
		child._parent = this;
		child.propagate();
	}

	Transform2D remove_child(Transform2D child)
	{
		auto existing = find(_children[], child);
		if (!existing.empty)
		{
			_children.linearRemove(take(existing, 1));
			child.parent = null;
			return existing.front;
		}
		return null;
	}

	unittest
	{
		Transform2D parent = new Transform2D;
		Transform2D child = new Transform2D;
		parent.add_child(child);
		parent.add_child(child);
		assert(walkLength(parent.children[]) == 2);
		assert(child.parent is parent);
		parent.remove_child(child);
		assert(walkLength(parent.children[]) == 1);
		assert(child.parent is null);
		parent.remove_child(child);
		assert(walkLength(parent.children[]) == 0);
		assert(child.parent is null);
	}

	@property Transform2D parent() { return _parent; }

	@property Transform2D parent(Transform2D val)
	{
		_parent = val;
		propagate();
		return _parent;
	}

	@property ref const(mat3x3d) local() const { return local_transform; }

	@property ref const(mat3x3d) global() const { return world_cache; }

	/// returns local scale
	@property vec2d scale() const { return _scale; }

	/// sets local scale
	@property vec2d scale(vec2d val)
	{
		_scale = val;
		rebuild();
		return _scale;
	}

	/// returns local rotation
	@property double rotation() const { return _rotation; }

	/// sets local rotation
	@property double rotation(double val)
	{
		_rotation = val;
		rebuild();
		return _rotation;
	}

	/// returns local translation
	@property vec2d translation() const { return _translation; }

	/// sets local translation
	@property vec2d translation(vec2d val)
	{
		_translation = val;
		rebuild();
		return _translation;
	}

	@property DList!Transform2D children() { return _children; }

	/// Initialize transform by individual components, applied in semantic order
	void from_components(vec2d scale, double rotation, vec2d translation)
	{
		_scale = scale;
		_rotation = rotation;
		_translation = translation;
		rebuild();
	}

	/// Recalculate transform matrixes from components and propagate changes
	/// to children.
	protected void rebuild()
	{
		local_transform = mat3x3d.scaling(_scale);
		local_transform = mat3x3d.rotateZ(_rotation) * local_transform;
		local_transform = mat3x3d.translation(_translation) * local_transform;
		propagate();
	}

	/// Transform local point into world space
	vec2d transform(vec2d point) const
	{
		vec3d homog = vec3d(point[0], point[1], 1.0);
		vec3d res = this.global * homog;
		return vec2d(res[0] / res[2], res[1] / res[2]);
	}

	/// Transform local angle into world angle
	double transform(double angle) const
	{
		vec2d v1 = vec2d(0, 0);
		vec2d v2 = vec2d(-sin(angle), cos(angle));
		auto dir = (transform(v2) - transform(v1)).normalized;
		if (abs(dir.x) < 0.6)	// precision of asin and acos requires attention
		{
			if (dir.y >= 0.0)
				return asin(-dir.x);
			else
				return PI + asin(dir.x);
		}
		else
		{
			if (dir.x >= 0.0)
				return -acos(dir.y);
			else
				return acos(dir.y);
		}
	}

	unittest
	{
		auto t = new Transform2D;
		t.rotation = -PI_2;
		assert(abs(t.transform(0.0) + PI_2) < 1e-6);
		assert(abs(t.transform(PI_2)) < 1e-6);
		assert(angleDist(t.transform(-PI_2) + PI, 0.0) < 1e-6);
	}
}


unittest
{
	import std.stdio;

	auto t = new Transform2D;
	t.scale = vec2d(2.0, 1.0);
	auto point = vec2d(1.0, 0.0);
	auto tpoint = t.transform(point);
	assert(abs(tpoint.x - 2.0) < 1e-6);
	assert(abs(tpoint.y - 0.0) < 1e-6);
	t.rotation = PI_2;
	tpoint = t.transform(point);
	assert(abs(tpoint.x - 0.0) < 1e-6);
	assert(abs(tpoint.y - 2.0) < 1e-6);
	t.translation = vec2d(3.0, 3.0);
	tpoint = t.transform(point);
	assert(abs(tpoint.x - 3.0) < 1e-6);
	assert(abs(tpoint.y - 5.0) < 1e-6);
	auto t_child = new Transform2D;
	t_child.translation = vec2d(1.0, 0.0);
	t.add_child(t_child);
	tpoint = t_child.transform(point);
	assert(abs(tpoint.x - 3.0) < 1e-6);
	assert(abs(tpoint.y - 7.0) < 1e-6);
	assert(abs(angleDist(t_child.transform(0.0), PI_2)) < 1e-6);
	t.remove_child(t_child);
	tpoint = t_child.transform(point);
	assert(abs(tpoint.x - 2.0) < 1e-6);
	assert(abs(tpoint.y - 0.0) < 1e-6);
}
