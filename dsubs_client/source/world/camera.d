module dsubs_client.world.camera;

import std.conv;
import std.math;

public import gfm.math.funcs;
public import gfm.math.vector;
public import gfm.math.matrix;

import derelict.sfml2.graphics;
import dsubs_client.core.sfml;
import dsubs_common.math.transform: clampAngle;


/// 2D-camera class, specializes on relative, iterative
/// transformations, caused by camera panning.
class Camera2D
{
	protected
	{
		// transformation from world-space to screen-space
		mat3x3d _mat;
		mat3x3d _imat;	// inverse, from screen to world
		// camera focus in world space
		vec2d _center;
		// rotation in world space. 0 - North, towards world Y axis. Positive
		// angle - counter-clockwise. Radians.
		double _rotation;
		// zoom. 1 - 1 unit in world space takes one pixel. 2.0 - 2 pixels.
		double _zoom;
		// screen size in pixels
		vec2ui _screen_size;

		// sfml-scpecific implementation
		sfView* _view;

		shared bool _dirty = false;
	}

	this(vec2ui screen_size = vec2ui(640, 480))
	{
		_view = sfView_create();
		from_components(vec2d(0, 0), 0, 1, screen_size);
	}

	~this()
	{
		sfView_destroy(_view);
	}

	protected void rebuild()
	{
		_dirty = false;
		mat3x3d res = mat3x3d.translation(-_center);
		res = mat3x3d.rotateZ(-_rotation) * res;
		// screen Y is inversed relative to world Y, hence the minus
		res = mat3x3d.scaling(vec2d(_zoom, -_zoom)) * res;
		_mat = mat3x3d.translation(vec2d(_screen_size) / 2.0) * res;
		_imat = _mat.inverse();
		// update view
		sfView_setCenter(_view, sfVector2f(_center.x, -_center.y));
		sfView_setRotation(_view, -degrees(_rotation));
		sfView_setSize(_view, tosf(_screen_size));
		sfView_zoom(_view, 1.0 / _zoom);
	}

	sfView* view() { return _view; }

	ref const(mat3x3d) world2screen()
	{
		if (_dirty)
			rebuild();
		return _mat;
	}

	ref const(mat3x3d) screen2world()
	{
		if (_dirty)
			rebuild();
		return _imat;
	}

	vec2d transform(vec2d world)
	{
		vec3d homog = vec3d(world.x, world.y, 1.0);
		vec3d rs = world2screen * homog;
		return vec2d(rs.x / rs.z, rs.y / rs.z);
	}

	vec2d inverse(vec2d screen)
	{
		vec3d homog = vec3d(screen.x, screen.y, 1.0);
		vec3d rs = screen2world * homog;
		return vec2d(rs.x / rs.z, rs.y / rs.z);
	}

	mixin template FieldDirtyProperty(T, string field_name, string assig="val")
	{
		mixin("@property " ~ T.stringof ~ " " ~ field_name ~
			"() const { return _" ~ field_name ~ ";};");
		mixin("@property " ~ T.stringof ~ " " ~ field_name ~ "(" ~
			T.stringof ~ " val) {" ~ "_" ~ field_name ~
			"=" ~ assig ~"; _dirty=true;" ~
			"return _" ~ field_name ~ ";}");
	}

	mixin FieldDirtyProperty!(vec2d, "center");
	mixin FieldDirtyProperty!(double, "rotation", "clampAngle(val)");
	mixin FieldDirtyProperty!(double, "zoom");
	mixin FieldDirtyProperty!(vec2ui, "screen_size");

	/// Pan camera by rotated, but not scaled translation vector
	/// For example, if shift=(1.0, 0.0), this method pans camera center
	/// towards right hand by 1 world-space unit.
	Camera2D pan(vec2d shift)
	{
		vec3d homog = vec3d(shift.x, shift.y, 1.0);
		vec3d rs = mat3x3d.rotateZ(_rotation) * homog;
		center = center + vec2d(rs.x / rs.z, rs.y / rs.z);
		return this;
	}

	void from_components(vec2d center, double rotation, double zoom, vec2ui screen)
	{
		_center = center;
		_rotation = rotation;
		_zoom = zoom;
		_screen_size = screen;
		rebuild();
	}
}

unittest
{
	import std.stdio;

	Camera2D camera = new Camera2D();
	vec2d center = camera.transform(vec2d(0.0, 0.0));
	assert(abs(center.x - 320) < 1);
	assert(abs(center.y - 240) < 1);
	vec2d left_top = camera.inverse(vec2d(0.0, 0.0));
	assert(abs(left_top.x + 320) < 1);
	assert(abs(left_top.y - 240) < 1);
	camera.zoom = 2.0;
	vec2d left = camera.transform(vec2d(-10.0, 0.0));
	assert(abs(left.x - 300) < 1);
	assert(abs(left.y - 240) < 1);
	camera.rotation = PI_2;
	left = camera.transform(vec2d(-10.0, 0.0));
	assert(abs(left.x - 320) < 1);
	assert(abs(left.y - 220) < 1);
	camera.pan(vec2d(10.0, 10.0));
	left = camera.transform(vec2d(-10.0, 0.0));
	assert(abs(left.x - 300) < 1);
	assert(abs(left.y - 240) < 1);
}
