module dsubs_sound.units;

import std.math;

/// Sound intensity (relative to reference intensity)
struct Intensity
{
	float val;
	alias val this;
}

/// Sound intensity level (db)
struct IntensityLevel
{
	float val;
	alias val this;
}

float toDb(float linear)
{
	return 10.0 * log10(linear);
}

float toLinear(float db)
{
	return pow(10.0, db / 10.0);
}

float pressureAmplitude(Intensity i)
{
	return sqrt(2 * i.val);
}