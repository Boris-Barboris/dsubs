module dsubs_common.api.utils;

import std.conv: to;

import dsubs_common.utils: ExceptionConstructors;


@safe:


/// UDA to decorate arrays and specify upper length limit.
struct MaxLenAttr
{
	int maxLength = 4096;
}

/// UDA to decorade mesages that are transparently compressed.
struct Compressed {}

class ProtocolException: Exception
{
	mixin ExceptionConstructors;
}

/// Thrown on marshalling\demarshalling of messages that violate array
/// length restrictions.
class MaxLenExceeded: ProtocolException
{
	int actualLength;
	int maxLength;

	private static string getMsg(int actual, int max)
	{
		return "max length " ~ max.to!string ~ ", actual " ~ actual.to!string;
	}

	this(int actual, int max, string file = __FILE__,
		size_t line = __LINE__, Throwable next = null)
	{
		super(getMsg(actual, max), file, line, next);
		actualLength = actual;
		maxLength = max;
	}

	this(int actual, int max, Throwable next, string file = __FILE__,
		size_t line = __LINE__)
	{
		super(getMsg(actual, max), file, line, next);
		actualLength = actual;
		maxLength = max;
	}
}