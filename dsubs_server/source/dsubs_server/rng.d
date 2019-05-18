module dsubs_server.rng;

import std.math;
import std.traits: isFloatingPoint;

public import std.random: uniform01, uniform;


/// sample standard normal distribution using Box-Muller transform
F rngStdNormal(F = double)()
	if (isFloatingPoint!F)
{
	static F prev;
	if (!isNaN(prev))
	{
		F res = prev;
		prev = F.nan;
		return res;
	}
	F u1 = uniform01();
	F u2 = uniform01();
	// save one of the results for later
	prev = sqrt(-2.0 * log(u1)) * sin(2.0 * PI * u2);
	return sqrt(-2.0 * log(u1)) * cos(2.0 * PI * u2);
}

/// generate normally-distributed random double
F rngNormal(F = double)(F mean = 0.0, F stddev = 1.0, F dlimit = 3.0,
	bool positive = true) if (isFloatingPoint!F)
{
	assert(stddev >= 0.0);
	assert(dlimit >= 0.0);
	F z0 = rngStdNormal!F();
	z0 = fmax(-dlimit, fmin(dlimit, z0));
	F ret = mean + z0 * stddev;
	if (positive)
		ret = fmax(0.0, ret);
	return ret;
}

/// Normally-distributed random floating point number
struct Rolled(F)
	if (isFloatingPoint!F)
{
	F mean = 0.0;
	F stddev = 1.0;

	this(F mean, F stddev)
	{
		this.mean = mean;
		this.stddev = stddev;
	}

	@property F roll() const
	{
		if (stddev == 0.0f)
			return mean;
		return rngNormal!F(mean, stddev);
	}

	alias roll this;
}

alias RolledF = Rolled!float;
alias RolledD = Rolled!double;