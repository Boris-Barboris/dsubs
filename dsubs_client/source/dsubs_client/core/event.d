module dsubs_client.core.event;

import std.traits: isDelegate, Parameters, ReturnType;

import dsubs_common.containers.array: removeFirst;


struct Event(DlgT)
	if (isDelegate!DlgT && is(ReturnType!DlgT == void))
{
	alias HandlerType = DlgT;
	alias ArgTypes = Parameters!DlgT;

	private HandlerType[] handlers;

	/// append or remove handler
	void opOpAssign(string op)(HandlerType handler)
	{
		static if (op == "+")
		{
			handlers ~= handler;
		}
		else static if (op == "-")
		{
			handlers.removeFirst!(a => a is handler);
		}
		else static assert(0, "Operator " ~ op ~ "= non-applicable to event");
	}

	/// forget about all handlers
	void clear()
	{
		handlers.length = 0;
	}

	void raise(ArgTypes args) const
	{
		foreach (handler; handlers)
			handler(args);
	}

	void opCall(ArgTypes args) const
	{
		raise(args);
	}
}


unittest
{
	Event!(void delegate(string)) event;
	string[] results;
	auto handler1 = (string s) { results ~= s; };
	auto handler2 = (string s) { results ~= s; };
	event += handler1;
	event += handler2;
	event.raise("test");
	assert(results.length == 2);
	event -= handler2;
	results = [];
	event.raise("test");
	assert(results.length == 1);
}
