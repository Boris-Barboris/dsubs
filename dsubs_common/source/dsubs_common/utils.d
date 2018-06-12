module dsubs_common.utils;


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