module dsubs_client.core.event;

import std.algorithm;
import std.traits;

import dsubs_client.containers.dlist;


struct Event(DelegateType : void delegate(ArgTypes), ArgTypes...)
	if (isDelegate!(DelegateType))
{
	alias HandlerType = void delegate(ArgTypes);
	private DList!HandlerType handlers;

	void opOpAssign(string op)(HandlerType handler)
	{
		static if (op == "+") handlers ~= handler;
		else static if (op == "-")
		{
			handlers.removePred(a => a is handler);
		}
		else static assert(0, "Operator " ~ op ~ "= non-applicable to event");
	}

	void raise(ArgTypes args)
	{
		foreach (handler; handlers)
			handler(args);
	}

	void opCall(ArgTypes args)
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
