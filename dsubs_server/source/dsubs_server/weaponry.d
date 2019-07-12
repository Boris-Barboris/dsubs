module dsubs_server.weaponry;

import std.algorithm;
import std.array: array;

import dsubs_common.api.entities;

import dsubs_server.common;
import dsubs_server.player;
import dsubs_server.submarine;


struct AmmoRoomPrototype
{
	int id;
	string name;
	int capacity;
	bool[string] allowedWeaponSet;

	AmmoRoomTemplate toTemplate() const
	{
		AmmoRoomTemplate res = AmmoRoomTemplate(id, name);
		res.capacity = capacity;
		res.allowedWeaponSet = WeaponSet(allowedWeaponSet.keys.array);
		return res;
	}
}


final class AmmoRoom
{
	this(AmmoRoomPrototype proto, WeaponCount[] loadout)
	{
		m_proto = proto;
		if (loadout.length > proto.allowedWeaponSet.length)
			throw new Exception("more weapon types than allowed");
		int weaponCount = loadout.map!(l => l.count).sum();
		if (weaponCount > proto.capacity)
			throw new Exception("room capacity exceeded");
		foreach (wc; loadout)
		{
			if (wc.weaponName !in proto.allowedWeaponSet)
				throw new Exception("weapon disallowed in this room");
			if (wc.count < 0)
				throw new Exception("negative weapon count");
			m_storedWeapons[wc.weaponName] = wc.count;
		}
	}

	private
	{
		AmmoRoomPrototype m_proto;
		int[string] m_storedWeapons;
	}

	@property int id() const { return m_proto.id; }

	// trusted input
	void putWeapon(string weaponName)
	{
		m_storedWeapons.update(weaponName,
			{ return 1; },
			(ref int count) { return count + 1; });
	}

	// Untrusted input. Returns true if operation was performed.
	bool removeWeapon(string weaponName)
	{
		int* count = weaponName in m_storedWeapons;
		if (count is null)
			return false;
		if (*count <= 0)
			return false;
		(*count)--;
		return true;
	}
}