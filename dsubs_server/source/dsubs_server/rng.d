module dsubs_server.rng;

import std.math;
import std.random;


/// generate normally-distributed random double using
/// Box-Muller transform
double rngNormal(double mean = 0.0, double stddev = 1.0, double dlimit = 3.0, 
	bool positive = true)
{
	assert(stddev > 0.0);
	assert(dlimit > 0.0);
	double u1 = uniform01();
	double u2 = uniform01();
	double z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * PI * u2);
	z0 = max(-dlimit, min(dlimit, z0));
	double ret = z0 * stddev + mean;
	if (positive)
		ret = max(0.0, ret);
	return ret;
}

/// Normally-distributed random variable
struct NormalDouble
{
	double mean = 0.0;
	double stddev = 1.0;
	private bool rolled;
	private double val;

	this(double mean, double stddev)
	{
		this.mean = mean;
		this.stddev = stddev;
	}

	@property double get()
	{
		if (rolled)
			return val;
		val = normal(mean, stddev);
		rolled = true;
		return val;
	}

	alias get this;
}