module dsubs_common.math;

public import std.math;
import std.traits: isNumeric;

public import dsubs_common.math.angles;
public import dsubs_common.math.transform;


@safe @nogc:

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