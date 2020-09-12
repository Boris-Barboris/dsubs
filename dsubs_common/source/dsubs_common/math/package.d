module dsubs_common.math;

public import std.math;
import std.traits: isNumeric, isFloatingPoint, Unqual;
import std.conv: to;

public import dsubs_common.math.angles;
public import dsubs_common.math.transform;


@safe:

double lerp(double a, double b, double x)
{
	return a + (b - a) * x;
}

/// clamp x between 0.0 and 1.0 and call lerp
double clerp(double a, double b, double x)
{
	x = clamp(x, 0.0, 1.0);
	return a + (b - a) * x;
}

/// Clamped move. Return cur moved towards tgt on speed spd as if dt time has passed
double cmove(double cur, double tgt, double spd, double dt)
{
	assert(spd >= 0.0);
	assert(dt >= 0.0);
	bool fwd = (tgt - cur) >= 0.0;
	double maxDelta = abs(tgt - cur);
	double availDelta = spd * dt;
	if (availDelta >= maxDelta)
		return tgt;
	if (fwd)
		return cur + spd * dt;
	else
		return cur - spd * dt;
}

VecT normalizedz(VecT)(const VecT rhs)
{
	if (rhs.x == 0.0 && rhs.y == 0.0)
		return VecT(0, 0);
	return rhs.normalized;
}

/// return v clamped between lower and upper
NumT clamp(NumT)(NumT v, NumT lower, NumT upper)
	if (isNumeric!NumT)
{
	assert(lower <= upper);
	if (v < lower)
		return lower;
	if (v > upper)
		return upper;
	return v;
}

unittest
{
	assert(clamp(-2.0, -1.0, 0.0) == -1.0);
	assert(clamp(2.0, -1.0, 0.0) == 0.0);
}

/// covert vec2f to vec2d
vec2d tod(vec2f v)
{
	return vec2d(v.x, v.y);
}

/// meters per second to knots
double mps2kts(double mps)
{
	return mps * 1.94384;
}

alias dB = float;

import core.stdc.math: powf, log10f;

/// linear ratio to decibels
pragma(inline, true)
float toDb(float linear)
{
	return 10.0f * log10f(linear);
}

/// decibels to linear ratio
pragma(inline, true)
float toLinear(float db)
{
	return powf(10.0f, db / 10.0f);
}

/// https://en.wikipedia.org/wiki/Cubic_Hermite_spline
auto chspline(FT, TT)(FT p0, FT p1, FT m0, FT m1, TT t, TT dt)
{
	assert(t >= 0.0 && t <= 1.0);
	double t_2 = t * t;
	double t_3 = t_2 * t;

	return (2 * t_3 - 3 * t_2 + 1) * p0 +
		(t_3 - 2 * t_2 + t) * dt * m0 +
		(-2 * t_3 + 3 * t_2) * p1 +
		(t_3 - t_2) * dt * m1;
}


@system:

/// Searches the root of f with binary division
float binarySearch(float delegate(float x) f, float startX = 0.0f,
	float startStep = 1.0f, int maxIter = 10)
{
	float res = startX;
	float leftFuncValue = f(startX);
	if (leftFuncValue == 0.0f)
		return res;
	float rightFuncValue;
	float step = startStep;
	int iter;
	while (++iter <= maxIter)
	{
		rightFuncValue = f(res + step);
		if (rightFuncValue == 0.0f)
		{
			res += step;
			break;
		}
		if (leftFuncValue * rightFuncValue < 0.0f)
		{
			// opposite sides of the root
			step /= 2.0f;
			continue;
		}
		if (fabs(leftFuncValue) > fabs(rightFuncValue))
		{
			// we're moving in the right direction
			res += step;
		}
		else
		{
			// we're moving in the wrong direction
			step = -step;
		}
	}
	return res;
}