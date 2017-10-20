module dsubs_common.math.transform;

import std.algorithm;
public import std.math;
import std.range;

public import gfm.math.matrix;
public import gfm.math.vector;

import dsubs_common.containers.array;


// Returns a - b, clamped to [-PI; PI]
double angleDist(double a, double b)
{
	double val = fmod(a - b, 2 * PI);
	if (abs(val) > PI)
		val -= sgn(val) * 2 * PI;
	return val;
}

pragma(inline):
double clampAngle(double a)
{
	return fmod(a, 2 * PI);
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
		shared bool dirty;		// set to true when some of parents changed
		mat3x3d world_cache;	// cached value of world-coordinates transform
		shared bool inverse_dirty;
		mat3x3d inverse_cache;	// inverted world matrix
		Transform2D _parent;
		Transform2D[] _children;
	}

	this()
	{
		from_components(vec2d(1.0, 1.0), 0.0, vec2d(0.0, 0.0));
	}

	/// Propagate the `dirty` signal from parent
	protected void propagate()
	{
		dirty = true;
		inverse_dirty = true;
		update_children();
	}

	protected void rebuild()
	{
		local_transform = mat3x3d.scaling(_scale);
		local_transform = mat3x3d.rotateZ(_rotation) * local_transform;
		local_transform = mat3x3d.translation(_translation) * local_transform;
		if (_parent)
			world_cache = _parent.global * local_transform;
		else
			world_cache = local_transform;
		dirty = false;
	}

	protected void calculate_inverse()
	{
		inverse_cache = global.inverse();
		inverse_dirty = false;
	}

	// Signal child transforms to recalculate their matrixes
	protected void update_children()
	{
		foreach (t; _children)
			t.inverse_dirty = t.dirty = true;
	}

	void add_child(Transform2D child)
	{
		_children ~= child;
		child._parent = this;
		child.propagate();
	}

	void remove_child(Transform2D kid)
	{
		bool removed = _children.removeFirst!(a => a is kid);
		if (removed)
			kid.parent = null;
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

	@property Transform2D parent() const { return _parent; }

	@property Transform2D parent(Transform2D val)
	{
		_parent = val;
		propagate();
		return _parent;
	}

	@property ref const(mat3x3d) local()
	{
		if (dirty)
			rebuild();
		return local_transform;
	}

	@property ref const(mat3x3d) global()
	{
		// lazy world transform recalculation
		if (dirty)
			rebuild();
		return world_cache;
	}

	@property ref const(mat3x3d) inversed()
	{
		// lazy inverse transform recalculation
		if (inverse_dirty)
			calculate_inverse();
		return inverse_cache;
	}

	/// returns local scale
	@property vec2d scale() const { return _scale; }

	/// sets local scale
	@property vec2d scale(vec2d val)
	{
		_scale = val;
		propagate();
		return _scale;
	}

	/// returns local rotation
	@property double rotation() const { return _rotation; }

	/// sets local rotation
	@property double rotation(double val)
	{
		_rotation = clampAngle(val);
		propagate();
		return _rotation;
	}

	/// returns local translation
	@property vec2d translation() const { return _translation; }

	/// sets local translation
	@property vec2d translation(vec2d val)
	{
		_translation = val;
		propagate();
		return _translation;
	}

	@property Transform2D[] children() { return _children; }

	/// Initialize transform by individual components, applied in semantic order
	void from_components(vec2d scale, double rotation, vec2d translation)
	{
		_scale = scale;
		_rotation = rotation;
		_translation = translation;
		propagate();
	}

	/// Transform point
	vec2d transform(vec2d point, bool inverse = false)
	{
		vec3d homog = vec3d(point[0], point[1], 1.0);
		vec3d res;
		if (inverse)
			res = this.inversed * homog;
		else
			res = this.global * homog;
		return vec2d(res[0] / res[2], res[1] / res[2]);
	}

	/// Transform direction
	vec2d direction(vec2d dir, bool inverse = false)
	{
		vec3d homog = vec3d(dir[0], dir[1], 0.0);
		vec3d res;
		if (inverse)
			res = this.inversed * homog;
		else
			res = this.global * homog;
		return vec2d(res[0], res[1]).normalized;
	}

	/// Transform local angle into world angle
	double transform(double angle, bool inverse = false)
	{
		vec2d v2 = vec2d(-sin(angle), cos(angle));
		auto dir = direction(v2, inverse);
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
		assert(abs(t.transform(-PI_2, true)) < 1e-6);
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
