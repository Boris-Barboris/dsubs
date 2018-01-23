module dsubs_server.rng;

import std.math;
import std.random;


/// sample standard normal distribution using Box-Muller transform
double rngStdNormal()
{
	static double prev;
	if (!isNaN(prev))
	{
		double res = prev;
		prev = double.nan;
		return res;
	}
	double u1 = uniform01();
	double u2 = uniform01();
	prev = sqrt(-2.0 * log(u1)) * sin(2.0 * PI * u2);
	return sqrt(-2.0 * log(u1)) * cos(2.0 * PI * u2);
}

/// generate normally-distributed random double
double rngNormal(double mean = 0.0, double stddev = 1.0, double dlimit = 3.0,
	bool positive = true)
{
	assert(stddev > 0.0);
	assert(dlimit > 0.0);
	double z0 = rngStdNormal();
	z0 = fmax(-dlimit, fmin(dlimit, z0));
	double ret = z0 * stddev + mean;
	if (positive)
		ret = fmax(0.0, ret);
	return ret;
}

/// Normally-distributed random double that gets rolled during runtime
struct NormalDouble
{
	const double mean = 0.0;
	const double stddev = 1.0;
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
		val = rngNormal(mean, stddev);
		rolled = true;
		return val;
	}

	alias get this;
}