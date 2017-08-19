module dsubs_client.core.component;

import core.atomic: atomicOp;


enum CompState: ubyte
{
	ON,			// component is active
	OFF,		// component is temporarily deactivated
	DELETED		// component is deactivated and should be disposed
}

class Component(string sysname)
{
	protected CompState _component_state = CompState.ON;

	CompState component_state() { return _component_state; }

	private void set_state(CompState new_state)
	{
		CompState old_state = _component_state;
		_component_state = new_state;
		if (old_state != new_state)
			on_state_change();
	}

	void deactivate()
	{
		assert(!deleted);
		set_state(CompState.OFF);
	}

	void activate()
	{
		assert(!deleted);
		set_state(CompState.ON);
	}

	void dispose()
	{
		assert(!deleted);
		set_state(CompState.DELETED);
	}

	void on_state_change() {}

	bool active() { return _component_state == CompState.ON; }
	bool inactive() { return _component_state == CompState.OFF; }
	bool deleted() { return _component_state == CompState.DELETED; }

	private static shared ulong id_counter = 0;
	private ulong _id;
	ulong id() { return _id; }

	alias ManagerType = ComponentManager!sysname;
	protected ManagerType _manager;

	this(ManagerType manager)
	{
		_manager = manager;
		_id = id_counter;
		atomicOp!"+="(id_counter, 1);
	}
}

class ComponentManager(string sysname)
{
	alias ComponentType = Component!sysname;

	/// Remove disposed components and recreate components array. Don't call this
	/// frequently.
	abstract void clear_disposed();
}
