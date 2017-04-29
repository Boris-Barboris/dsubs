module dsubs_client.core.component;

import std.algorithm;
import std.array;
import std.range;


enum CompState: ubyte
{
	ON,			// component is active
	OFF,		// component is temporarily deactivated
	DELETED		// component is disposed
}

class Component(string sysname)
{
	protected CompState _state;

	CompState state() { return _state; }

	bool active() { return _state == CompState.ON; }

	CompState setState(CompState new_state)
	{
		_state = new_state;
		return _state;
	}

	alias ManagerType = ComponentManager!sysname;
	protected ManagerType _manager;

	this(ManagerType manager)
	{
		_state = CompState.ON;
		_manager = manager;
		synchronized (manager)
		{
			_manager.components ~= this;
		}
	}
}

class ComponentManager(string sysname)
{
	alias ComponentType = Component!sysname;

	protected ComponentType[] components;

	/// Remove disposed components and recreate components array. Don't call this
	/// frequently.
	uint clear_disposed()
	{
		synchronized (this)
		{
			auto old_comps = components;
			components = array(remove!(a => a.state == CompState.DELETED)(components));
			return old_comps.length - components.length;
		}
	}

	// get range containing active components
	auto active_comps()
	{
		return filter!(a => a.state == CompState.ON)(components);
	}
}


unittest
{
	auto mgr = new ComponentManager!"test"();
	auto cmp = new Component!"test"(mgr);
	assert(mgr.active_comps.takeOne[0] is cmp);
}
