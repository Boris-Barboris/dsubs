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

/// approximation of Error function.
// https://en.wikipedia.org/wiki/Error_function#Approximation_with_elementary_functions
Unqual!F erf(F)(F x)
	if (isFloatingPoint!(F))
{
	bool neg = x < 0.0;
	x = abs(x);
	// if (x > 10)
	// 	return neg ? -1 : 1;
	F res = 1.0 - 1.0 /
		pow(1.0 + 0.278393 * x + 0.230389 * pow(x, 2) +
		0.000972 * pow(x, 3) + 0.078108 * pow(x, 4), 4);
	assert(res >= 0 && res < 1, res.to!string ~ " on " ~ x.to!string);
	// res = fmax(-1, fmin(1, res));
	return neg ? -res : res;
}

/// meters per second to knots
double mps2kts(double mps)
{
	return mps * 1.94384;
}