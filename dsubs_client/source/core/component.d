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
	protected CompState _state = CompState.ON;

	CompState state() { return _state; }

	Component state(CompState val)
	{
		_state = val;
		return this;
	}

	bool active() { return _state == CompState.ON; }
	bool deleted() { return _state == CompState.DELETED; }

	CompState setState(CompState new_state)
	{
		_state = new_state;
		return _state;
	}

	alias ManagerType = ComponentManager!sysname;
	protected ManagerType _manager;

	this(ManagerType manager)
	{
		_manager = manager;
	}
}

class ComponentManager(string sysname)
{
	alias ComponentType = Component!sysname;

	/// Remove disposed components and recreate components array. Don't call this
	/// frequently.
	abstract void clear_disposed();
}
