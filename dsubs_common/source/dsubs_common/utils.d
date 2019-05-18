module dsubs_common.utils;

public import std.experimental.logger: info, trace, error, warning;

import std.math: isNaN, isInfinity;
import std.exception: enforce;


/// Standard std-like exception constructors
mixin template ExceptionConstructors()
{
	@safe pure nothrow this(string message,
							Throwable next,
							string file =__FILE__,
							size_t line = __LINE__)
	{
		super(message, next, file, line);
	}

	@safe pure nothrow this(string message,
							string file =__FILE__,
							size_t line = __LINE__,
							Throwable next = null)
	{
		super(message, file, line, next);
	}
}


auto validateFloat(T)(const T val)
	if (is(T == float) || is(T == double))
{
	enforce(!isNaN(val), "NaN poisoning");
	enforce(!isInfinity(val), "infinity poisoning");
	return val;
}