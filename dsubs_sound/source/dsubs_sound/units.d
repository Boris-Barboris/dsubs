module dsubs_sound.units;

import std.math;


/// Sound intensity (relative to reference intensity)
struct Intensity
{
	float val;
	alias val this;

	IntensityLevel toDb() const
	{
		return IntensityLevel(val.toDb());
	}
}

/// Sound intensity level (db)
struct IntensityLevel
{
	dB val;
	alias val this;

	Intensity toLinear() const
	{
		return Intensity(val.toLinear());
	}
}

float toDb(float linear)
{
	return 10.0 * log10(linear);
}

float toLinear(float db)
{
	return pow(10.0, db / 10.0);
}

alias dB = float;