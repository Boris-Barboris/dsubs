module dsubs_common.event;

import std.traits: isDelegate, Parameters, ReturnType;

import dsubs_common.containers.array: removeFirst;


/// Collection of subscribed delegates that can be raised.
struct Event(DlgT)
	if (isDelegate!DlgT && is(ReturnType!DlgT == void))
{
	alias HandlerType = DlgT;
	alias ArgTypes = Parameters!DlgT;

	private HandlerType[] handlers;

	/// Append or remove handler
	void opOpAssign(string op)(HandlerType handler)
	{
		static if (op == "+")
		{
			handlers ~= handler;
		}
		else static if (op == "-")
		{
			handlers.removeFirst(handler);
		}
		else static assert(0, "Operator " ~ op ~ "= non-applicable to event");
	}

	void subscribe(HandlerType handler)
	{
		handlers ~= handler;
	}

	/// Release all subscribers
	void clear()
	{
		handlers.length = 0;
	}

	/// Call all subscribers
	void raise(ArgTypes args) const
	{
		foreach (handler; handlers)
			handler(args);
	}

	/// ditto
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
