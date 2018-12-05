module dsubs_sound.units;

import std.math;
import core.stdc.math: powf, log10f;

import dsubs_common.math;


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