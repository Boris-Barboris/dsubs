module dsubs_common.math.angles;

import std.algorithm;
import std.math;

public import gfm.math.vector;


@safe:

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

/// Clamp angle into [-PI, PI] interval
double clampAnglePi(double a)
{
	a = fmod(a, 2 * PI);
	if (a > PI)
		a -= 2 * PI;
	else if (a < -PI)
		a += 2 * PI;
	return a;
}

unittest
{
	assert(abs(angleDist(clampAngle(0.5 + 2 * PI), 0.5)) < 0.01);
	assert(abs(angleDist(clampAngle(-0.5 - 2 * PI), -0.5)) < 0.01);
	assert(abs(angleDist(clampAnglePi(-0.5 - PI), PI - 0.5)) < 0.01);
}

/// Clamp direction into [-2 * PI, 0] interval
double compassAngle(double a)
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

/// Get the angle between dir and (0.0, 1.0) vector, clamped to [-PI, PI].
double courseAngle(vec2d dir)
{
	return atan2(-dir.x, dir.y);
}

/// ditto
float courseAngle(vec2f dir)
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

/// Unit vector wich corresponds to course angle
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

/// Sector consists of two beams and area between them. Sector can be full circle.
/// Area between beams spans clockwise - from left beam to right beam.
struct Sector
{
	float left;		/// left beam, radians
	float right;	/// right beam, radians
	private float angle; // always non-positive

	void normalize()
	{
		angle = angleDist(right, left);
		if (angle > 0)
			angle -= 2 * PI;
		assert(!isNaN(angle));
		assert(angle < 0);
		left = clampAnglePi(left);
		right = left + angle;
	}
}

struct Projection
{
	float left;		// [0;1]
	float right;	// [left;1]
}

/// Two sectors is zero, one or two subsectors. This structure contains
/// projection of those subsectors onto the 'onto' sector.
struct SectorProjection
{
	int count = 0;
	Projection[2] proj;
}

/// ditto
SectorProjection projectSectorsIntersect(Sector what, Sector onto)
{
	SectorProjection res;
	what.normalize();
	onto.normalize();

	static struct Ray
	{
		int sector;
		float dir;
	}

	Ray[6] rays;
	rays[0] = Ray(0, what.left);
	rays[1] = Ray(0, what.right);
	rays[2] = Ray(1, onto.left);
	rays[3] = Ray(1, onto.right);
	rays[4] = Ray(1, onto.left - 2 * PI);
	rays[5] = Ray(1, onto.right - 2 * PI);

	sort!"a.dir > b.dir"(rays[]);

	version(unittest)
	{
		import std.stdio;
		writeln(rays[]);
	}

	bool insideWhat;
	bool insideOnto;
	float left;
	for (int i = 0; i < 6; i++)
	{
		int raySector = rays[i].sector;
		if (insideOnto && insideWhat)
		{
			// we have met an end of an intersection
			float normStart = (rays[i-1].dir - left) / onto.angle;
			float normEnd = (rays[i].dir - left) / onto.angle;
			version(unittest)
			{
				assert(!isNaN(normStart));
				assert(!isNaN(normEnd));
				assert(normStart >= 0.0f);
				assert(normStart <= normEnd);
				assert(normEnd <= 1.0f);
				assert(res.count <= 1);
			}
			res.proj[res.count].left = normStart;
			res.proj[res.count].right = normEnd;
			res.count++;
		}
		if (raySector == 0)
			insideWhat = !insideWhat;
		else if (raySector == 1)
		{
			if (!insideOnto)
				left = rays[i].dir;
			insideOnto = !insideOnto;
		}
	}

	return res;
}

unittest
{
	import std.stdio;

	auto proj = projectSectorsIntersect(Sector(0, -PI_2), Sector(PI_2, -PI_2));
	writeln(proj);
	assert(proj.count == 1);
	assert((proj.proj[0].left - 0.5f).fabs < 1e-4);
	assert((proj.proj[0].right - 1.0f).fabs < 1e-4);

	proj = projectSectorsIntersect(Sector(1, -1), Sector(0.5, -0.5));
	writeln(proj);
	assert(proj.count == 1);
	assert((proj.proj[0].left - 0.0f).fabs < 1e-4);
	assert((proj.proj[0].right - 1.0f).fabs < 1e-4);

	proj = projectSectorsIntersect(Sector(-0.1, 0.1), Sector(PI - 0.1, -PI + 0.1));
	writeln(proj);
	assert(proj.count == 2);
	assert((proj.proj[0].left - 0.516f).fabs < 1e-2);
	assert((proj.proj[0].right - 1.0f).fabs < 1e-4);
	assert((proj.proj[1].left - 0.0f).fabs < 1e-4);
	assert((proj.proj[1].right - 0.48f).fabs < 1e-2);
}