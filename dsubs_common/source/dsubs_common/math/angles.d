module dsubs_common.math.angles;

import std.math;

public import gfm.math.vector;


/// Return a - b, clamped to [-PI; PI].
/// Equal to smallest direction change from b to a.
double angleDist(double a, double b)
{
	double val = fmod(a - b, 2 * PI);
	if (abs(val) > PI)
		val -= sgn(val) * 2 * PI;
	return val;
}

unittest
{
	assert(abs(angleDist(-PI, PI + 0.001)) < 0.01);
	assert(angleDist(-PI, PI + 0.001) < 0.0);
	assert(abs(angleDist(PI, -PI - 0.001)) < 0.01);
	assert(angleDist(PI, -PI - 0.001) > 0.0);
}

/// Clamp angle into [-2 * PI, 2 * PI] interval
double clampAngle(double a)
{
	return fmod(a, 2 * PI);
}

unittest
{
	assert(abs(angleDist(clampAngle(0.5 + 2 * PI), 0.5)) < 0.01);
	assert(abs(angleDist(clampAngle(-0.5 - 2 * PI), -0.5)) < 0.01);
}

/// Clamp angle into [-2 * PI, 0] interval
double courseAngle(double a)
{
	double val = clampAngle(a);
	if (val > 0)
		val -= 2 * PI;
	return val;
}

double rad2dgr(double rad)
{
	return rad * 180.0 / PI;
}

double dgr2rad(double dgr)
{
	return dgr / 180.0 * PI;
}

/// Get the angle between dir and (0, 1.0) vector
double courseAngle(vec2d dir)
{
	return atan2(-dir.x, dir.y);
}

unittest
{
	assert(courseAngle(vec2d(0.0, 1.0)) == 0.0);
	assert(abs(angleDist(courseAngle(vec2d(-1.0, 0.0)), PI_2)) < 0.01);
	assert(abs(angleDist(courseAngle(vec2d(3.0, 0.0)), -PI_2)) < 0.01);
	assert(abs(angleDist(courseAngle(vec2d(-0.01, -1.0)), PI)) < 0.01);
	assert(abs(angleDist(courseAngle(vec2d(0.01, -1.0)), -PI)) < 0.01);
}

/// Unit vector, facing course angle
vec2d courseVector(double c)
{
	return vec2d(-sin(c), cos(c));
}

vec2d rotateVector(vec2d v, double rot)
{
	double course = courseAngle(v) + rot;
	double len = v.length;
	return len * courseVector(course);
}

unittest
{
	assert((vec2d(-1.0, 0.0) - rotateVector(vec2d(0.0, 1.0), PI_2)).length < 0.001);
}