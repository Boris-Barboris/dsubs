module dsubs_client.world.camera;

import std.conv;
import std.math;

public import gfm.math.vector;
public import gfm.math.matrix;


/// 2D-camera class, specializes on relative, iterative
/// transformations, caused by camera panning.
class Camera2D
{
	protected
	{
		// transformation from world-space to screen-space
		mat3x3f _mat;
		mat3x3f _imat;	// inverse, from screen to world
		// camera focus in world space
		vec2f _center;
		// rotation in world space. 0 - North, towards world Y axis. Positive
		// angle - counter-clockwise.
		float _rotation;
		// zoom. 1 - 1 unit in world space takes one pixel. 2.0 - 2 pixels.
		float _zoom;
		// screen size in pixels
		vec2ui _screen_size;

		bool _dirty = false;
	}

	this(vec2ui screen_size = vec2ui(640, 480))
	{
		from_components(vec2f(0, 0), 0, 1, screen_size);
	}

	protected void rebuild()
	{
		mat3x3f res;
		_dirty = false;
		res = mat3x3f.translation(-_center);
		res = mat3x3f.rotateZ(-_rotation) * res;
		// screen Y is inversed relative to world Y, hence the minus
		res = mat3x3f.scaling(vec2f(_zoom, -_zoom)) * res;
		_mat = mat3x3f.translation(vec2f(_screen_size) / 2.0) * res;
		_imat = _mat.inverse();
	}

	ref const(mat3x3f) world2screen()
	{
		if (_dirty)
			rebuild();
		return _mat;
	}

	ref const(mat3x3f) screen2world()
	{
		if (_dirty)
			rebuild();
		return _imat;
	}

	vec2f transform(vec2d world)
	{
		vec3f homog = vec3f(to!float(world.x), to!float(world.y), 1.0);
		vec3f rs = world2screen * homog;
		return vec2f(rs.x / rs.z, rs.y / rs.z);
	}

	vec2d inverse(vec2f screen)
	{
		vec3f homog = vec3f(screen.x, screen.y, 1.0);
		vec3f rs = screen2world * homog;
		return vec2d(rs.x / rs.z, rs.y / rs.z);
	}

	mixin template FieldDirtyProperty(T, string field_name)
	{
		mixin("@property " ~ T.stringof ~ " " ~ field_name ~
			"() const { return _" ~ field_name ~ ";};");
		mixin("@property " ~ T.stringof ~ " " ~ field_name ~ "(" ~
			T.stringof ~ " val) {" ~ "_" ~ field_name ~
			"=val; _dirty=true;" ~
			"return _" ~ field_name ~ ";}");
	}

	mixin FieldDirtyProperty!(vec2f, "center");
	mixin FieldDirtyProperty!(float, "rotation");
	mixin FieldDirtyProperty!(float, "zoom");
	mixin FieldDirtyProperty!(vec2ui, "screen_size");

	/// Pan camera by rotated, but not scaled translation vector
	/// For example, if shift=(1.0, 0.0), this method pans camera center
	/// towards right hand by 1 world-space unit.
	Camera2D pan(vec2f shift)
	{
		vec3f homog = vec3f(shift.x, shift.y, 1.0);
		vec3f rs = mat3x3f.rotateZ(_rotation) * homog;
		center = center + vec2f(rs.x / rs.z, rs.y / rs.z);
		return this;
	}

	void from_components(vec2f center, float rotation, float zoom, vec2ui screen)
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
	vec2f center = camera.transform(vec2d(0.0, 0.0));
	assert(abs(center.x - 320) < 1);
	assert(abs(center.y - 240) < 1);
	vec2d left_top = camera.inverse(vec2f(0.0, 0.0));
	assert(abs(left_top.x + 320) < 1);
	assert(abs(left_top.y - 240) < 1);
	camera.zoom = 2.0;
	vec2f left = camera.transform(vec2d(-10.0, 0.0));
	assert(abs(left.x - 300) < 1);
	assert(abs(left.y - 240) < 1);
	camera.rotation = PI_2;
	left = camera.transform(vec2d(-10.0, 0.0));
	assert(abs(left.x - 320) < 1);
	assert(abs(left.y - 220) < 1);
	camera.pan(vec2f(10.0, 10.0));
	left = camera.transform(vec2d(-10.0, 0.0));
	assert(abs(left.x - 300) < 1);
	assert(abs(left.y - 240) < 1);
}
