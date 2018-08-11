module dsubs_sound.units;

import std.math;
import core.stdc.math: powf, log10f;


/// Sound intensity (relative to reference intensity)
struct Intensity
{
	float val = 0.0f;
	alias val this;

	IntensityLevel toDb() const
	{
		return IntensityLevel(val.toDb());
	}
}

/// Sound intensity level (db)
struct IntensityLevel
{
	dB val = 0.0f;
	alias val this;

	Intensity toLinear() const
	{
		return Intensity(val.toLinear());
	}
}

pragma(inline, true)
float toDb(float linear)
{
	return 10.0f * log10f(linear);
}

pragma(inline, true)
float toLinear(float db)
{
	return powf(10.0f, db / 10.0f);
}

alias dB = float;