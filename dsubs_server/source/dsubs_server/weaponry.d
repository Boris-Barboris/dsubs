
/*
DSubs
Copyright (C) 2017-2025 Baranin Alexander

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
module dsubs_server.weaponry;

import std.algorithm;
import std.array: array;
import std.json;

import dsubs_common.api.entities;
import dsubs_common.math;

import dsubs_sound.soundsource;
import dsubs_sound.common;
import dsubs_sound.hydrophone: IFlowNoiseMultiplier;

import dsubs_server.common;
import dsubs_server.acoustics: PrerecordedSoundConfig;
import dsubs_server.player;
import dsubs_server.torpedo;
import dsubs_server.vessel: MountPointConfig;
import dsubs_server.objfile: ObjModel;
import dsubs_server.submarine;


struct AmmoRoomPrototype
{
	int id;
	string name;
	int capacity;
	TubeType roomType;
	string[] allowedWeaponSet;

	@property const(AmmoRoomTemplate) tmpl() const
	{
		return const AmmoRoomTemplate(id, name,
			const WeaponSet(allowedWeaponSet), capacity);
	}
}


final class AmmoRoom
{
	// untrusted 'loadout' input
	this(Submarine owner, const AmmoRoomPrototype proto, const(WeaponCount)[] loadout)
	{
		m_sub = owner;
		m_proto = proto;
		if (loadout.length > proto.allowedWeaponSet.length)
			throw new Exception("more weapon types than allowed");
		int weaponCount = loadout.map!(l => l.count).sum();
		if (weaponCount > proto.capacity)
			throw new Exception("room capacity exceeded");
		foreach (wc; loadout)
		{
			if (!canFind(proto.allowedWeaponSet, wc.weaponName))
				throw new Exception("weapon disallowed in this room");
			if (wc.count < 0)
				throw new Exception("negative weapon count");
			m_storedWeapons[wc.weaponName] = wc.count;
		}
	}

	private
	{
		Submarine m_sub;
		const AmmoRoomPrototype m_proto;
		int[string] m_storedWeapons;
	}

	@property int id() const { return m_proto.id; }
	@property Submarine submarine() { return m_sub; }

	/// number of stored weapons
	@property int weaponCount() const
	{
		return m_storedWeapons.values.sum;
	}

	/// storage capacity
	@property int capacity() const
	{
		return m_proto.capacity;
	}

	@property ref const(AmmoRoomPrototype) prototype() const
	{
		return m_proto;
	}

	string getRandomWeapon() const
	{
		if (weaponCount == 0)
			return null;
		auto kvpairs = m_storedWeapons.byKeyValue.array;
		size_t randomIdx = dsubs_sound.common.uniform!("[)", size_t, size_t)(
			0, kvpairs.length);
		return kvpairs[randomIdx].key;
	}

	int getWeaponCount(string weaponName)
	{
		int* res = weaponName in m_storedWeapons;
		if (res)
			return *res;
		return 0;
	}

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

	@property AmmoRoomFullState fullState() const
	{
		AmmoRoomFullState res = AmmoRoomFullState(m_proto.id);
		foreach (kvPair; m_storedWeapons.byKeyValue)
			res.storedWeapons ~= WeaponCount(kvPair.key, kvPair.value);
		return res;
	}
}


struct TubeConfig
{
	TubeTemplate tmpl;
	MountPointConfig mountPointConfig;
	usecs_t loadTime;
	usecs_t floodTime;
	usecs_t openTime;
	usecs_t firingTime;
	PrerecordedSoundConfig floodSoundConfig;
	PrerecordedSoundConfig openSoundConfig;
	PrerecordedSoundConfig firingSoundConfig;
	float openFlowNoiseMult = 1.0f;

	void setCenterFromModel(ref const ObjModel model)
	{
		mountPointConfig.setCenterFromModel(model);
		tmpl.mount = mountPointConfig.mountPoint;
	}
}

struct TubeOperationResult
{
	bool tubeChanged;
	bool roomChanged;
	bool launchOccurred;
	string launchedWeaponName;
	string wireGuidanceId;	/// set if wireWasCut as well
	bool wireWasCut;
}


/// Tube that launches weapons
final class Tube: IFlowNoiseMultiplier
{
	// untrusted 'initialWeapon' input
	this(Submarine owner, AmmoRoom room, const TubeConfig config, string initialWeapon)
	{
		m_sub = owner;
		m_proto = config;
		m_room = room;
		enforce(initialWeapon == null ||
			canFind(room.m_proto.allowedWeaponSet, initialWeapon),
			"weapon cannot be stored in the room");
		m_loadedWeapon = m_desiredWeapon = initialWeapon;
		if (initialWeapon)
		{
			assert(m_proto.tmpl.type == TubeType.decoy);
			m_state = TubeState.open;
			m_desiredState = m_state;
		}
		m_transform = new Transform2D();
		m_transform.position = m_proto.tmpl.mount.mountCenter.to!vec2d;
		m_transform.rotation = m_proto.tmpl.mount.rotation;
		m_sub.transform.addChild(m_transform);
	}

	private
	{
		Transform2D m_transform;
		Submarine m_sub;
		AmmoRoom m_room;
		Weapon m_wireGuidedWeapon;
		const TubeConfig m_proto;
		string m_loadedWeapon;
		string m_desiredWeapon;
		float m_pushSpeed = 10.0f;
		usecs_t m_transitionTimeCounter;

		TubeState m_state = TubeState.dry;
		TubeState m_desiredState = TubeState.dry;
		// used to send updates after the simulation step is done
		TubeOperationResult m_lastSimUpdateResults;
	}

	JSONValue toJson()
	{
		JSONValue[string] objectFields;
		JSONValue res = JSONValue(objectFields);
		res["id"] = m_proto.tmpl.id;
		res["type"] = m_proto.tmpl.type.to!string;
		res["roomId"] = m_proto.tmpl.roomId;
		res["loadedWeapon"] = loadedWeapon;
		res["desiredWeapon"] = desiredWeapon;
		res["transitionTimeCounter"] = m_transitionTimeCounter;
		res["state"] = m_state.to!string;
		res["desiredState"] = m_desiredState.to!string;
		return res;
	}

	override float getFlowNoiseMult() const
	{
		if (m_state == TubeState.open ||
			m_state == TubeState.closing ||
			m_state == TubeState.opening)
		{
			return m_proto.openFlowNoiseMult;
		}
		return 1.0f;
	}

	@property int id() const { return m_proto.tmpl.id; }
	@property Submarine submarine() { return m_sub; }
	@property Transform2D transform() { return m_transform; }
	@property inout(AmmoRoom) room() inout { return m_room; }
	@property TubeState state() const { return m_state; }
	@property TubeState desiredState() const { return m_desiredState; }
	@property TubeType type() const { return m_proto.tmpl.type; }
	@property bool wireGuidanceActive() const { return m_wireGuidedWeapon !is null; }
	@property bool wireGuidanceSupported() const { return m_proto.tmpl.wireGuidance; }
	@property string wireGuidanceId() const
	{
		if (m_wireGuidedWeapon)
			return m_wireGuidedWeapon.id.toString;
		return null;
	}
	@property string wireGuidedWeaponName() const
	{
		if (m_wireGuidedWeapon)
			return m_wireGuidedWeapon.prototypeName;
		return null;
	}
	@property Weapon wireGuidedWeapon() { return m_wireGuidedWeapon; }
	@property string loadedWeapon() const { return m_loadedWeapon; }
	@property string desiredWeapon() const { return m_desiredWeapon; }
	@property TubeOperationResult lastSimUpdateResult() const
	{
		return m_lastSimUpdateResults;
	}

	@property TubeFullState fullState() const
	{
		return TubeFullState(
			id, m_loadedWeapon, m_desiredWeapon, m_state, m_desiredState,
			wireGuidanceActive, wireGuidedWeaponName, wireGuidanceId);
	}

	TubeOperationResult processLoadRequest(string newWeaponName)
	{
		if (newWeaponName == m_desiredWeapon)
			return TubeOperationResult(false, false);
		enforce(newWeaponName == null ||
			canFind(m_room.m_proto.allowedWeaponSet, newWeaponName),
			"invalid weapon");
		// check if we need to start unloading
		switch (m_state)
		{
			case TubeState.dry:
			{
				if (m_loadedWeapon == newWeaponName)
					return TubeOperationResult(false, false);
				if (m_loadedWeapon)
				{
					// start unloading old weapon
					m_state = TubeState.unloading;
					m_desiredWeapon = newWeaponName;
					return TubeOperationResult(true, false);
				}
				// try to start loading new weapon
				if (m_room.removeWeapon(newWeaponName))
				{
					m_state = TubeState.loading;
					m_loadedWeapon = newWeaponName;
					m_desiredWeapon = newWeaponName;
					return TubeOperationResult(true, true);
				}
				else
					return TubeOperationResult(false, false);
			}
			case TubeState.unloading:
			{
				m_desiredWeapon = newWeaponName;
				// check if we need to abort unloading and start loading current
				// weapon again.
				if (m_loadedWeapon == m_desiredWeapon)
				{
					m_state = TubeState.loading;
					m_transitionTimeCounter = max(0,
						m_proto.loadTime - m_transitionTimeCounter);
				}
				return TubeOperationResult(true, false);
			}
			case TubeState.loading:
			{
				m_desiredWeapon = newWeaponName;
				// we need to abort loading and start unloading current
				// weapon again.
				m_state = TubeState.unloading;
				m_transitionTimeCounter = max(0,
					m_proto.loadTime - m_transitionTimeCounter);
				return TubeOperationResult(true, false);
			}
			default:
				// wrong state
				return TubeOperationResult(false, false);
		}
	}

	TubeOperationResult processStateRequest(TubeState newDesiredState)
	{
		enforce(isStableState(newDesiredState), "unstable state specified as desired");
		if (m_desiredState == newDesiredState)
			return TubeOperationResult(false, false);
		switch (m_state)
		{
			case TubeState.dry:
			case TubeState.flooded:
			case TubeState.open:
			case TubeState.flooding:
			case TubeState.drying:
			case TubeState.opening:
			case TubeState.closing:
			case TubeState.firing:
			{
				m_desiredState = newDesiredState;
				return TubeOperationResult(true, false);
			}
			default:
				// we do not allow desired state switch during loading/unloading
				return TubeOperationResult(false, false);
		}
	}

	// atomic weapon launch
	TubeOperationResult processLaunchRequest(string expectedWeapon,
		const(WeaponParamValue)[] weaponParams)
	{
		if (m_state != TubeState.open || m_loadedWeapon != expectedWeapon)
			return TubeOperationResult(false, false);
		enforce(m_loadedWeapon != null, "no weapon is loaded");
		const WeaponFactory wf = Globals.entityDb.getWeaponFactory(m_loadedWeapon);
		Weapon w = wf.build(m_sub, weaponParams, this);
		w.transform.position = m_transform.wposition;
		w.transform.rotation = m_transform.wrotation;
		w.rigidBody.kinet.vel = m_sub.rigidBody.fixedPointVelocity(m_transform.wposition) +
			m_pushSpeed * m_transform.wforward;
		w.rigidBody.kinet.angVel = m_sub.rigidBody.kinet.angVel;
		w.register(m_sub.simulator);
		m_desiredWeapon = m_loadedWeapon = null;
		m_state = TubeState.firing;
		if (wireGuidanceSupported && wf.wireGuided)
			m_wireGuidedWeapon = w;
		size_t soundOffset = dsubs_sound.common.uniform!("[]", size_t, size_t)(
			0, GLOBAL_SRATE / 8);
		startPlayingSound(m_proto.firingSoundConfig, &soundOffset);
		TubeOperationResult res = TubeOperationResult(
			true, false, true, wf.name, wireGuidanceId, false);
		return res;
	}

	/// Creates sounds on the start of state transitions
	void onPreKinematics()
	{
		m_lastSimUpdateResults = TubeOperationResult();
		if (m_desiredState != m_state && m_transitionTimeCounter == 0)
		{
			if (isStableState(m_state))
			{
				m_lastSimUpdateResults.tubeChanged = true;
				startTransitionToDesiredState();
			}
		}
	}

	/// Called when torpedo is detonated or is out of fuel.
	/// If wpn is null, cut any wire.
	void handleWireCut(Weapon wpn)
	{
		if ((wpn is null && m_wireGuidedWeapon) || m_wireGuidedWeapon is wpn)
		{
			if (m_state == TubeState.open || m_state == TubeState.firing)
			{
				m_desiredState = TubeState.dry;
				m_lastSimUpdateResults.tubeChanged = true;
			}
			m_lastSimUpdateResults.wireWasCut = true;
			m_lastSimUpdateResults.wireGuidanceId = wireGuidanceId;
			m_wireGuidedWeapon = null;
		}
	}

	private void updateTransientState()
	{
		final switch (m_state)
		{
			case TubeState.unloading:
			{
				if (m_transitionTimeCounter >= m_proto.loadTime)
				{
					// unload finished
					m_transitionTimeCounter = 0;
					assert(m_loadedWeapon);
					m_room.putWeapon(m_loadedWeapon);
					m_lastSimUpdateResults.tubeChanged = true;
					m_lastSimUpdateResults.roomChanged = true;
					if (m_desiredWeapon && m_room.removeWeapon(m_desiredWeapon))
					{
						// desired weapon was atomically taken from the room,
						// start loading.
						m_loadedWeapon = m_desiredWeapon;
						m_state = TubeState.loading;
					}
					else
					{
						// we are dry and empty
						m_loadedWeapon = m_desiredWeapon = null;
						m_state = TubeState.dry;
					}
				}
				break;
			}
			case TubeState.loading:
			{
				if (m_transitionTimeCounter >= m_proto.loadTime)
				{
					// load finished
					m_transitionTimeCounter = 0;
					assert(m_desiredWeapon == m_loadedWeapon);
					m_lastSimUpdateResults.tubeChanged = true;
					m_state = TubeState.dry;
				}
				break;
			}
			case TubeState.flooding:
			{
				if (m_transitionTimeCounter >= m_proto.floodTime)
				{
					// flood finished
					m_transitionTimeCounter = 0;
					m_lastSimUpdateResults.tubeChanged = true;
					m_state = TubeState.flooded;
				}
				break;
			}
			case TubeState.drying:
			{
				if (m_transitionTimeCounter >= m_proto.floodTime)
				{
					// drying finished
					m_transitionTimeCounter = 0;
					m_lastSimUpdateResults.tubeChanged = true;
					m_state = TubeState.dry;
				}
				break;
			}
			case TubeState.opening:
			{
				if (m_transitionTimeCounter >= m_proto.openTime)
				{
					// opening finished
					m_transitionTimeCounter = 0;
					m_lastSimUpdateResults.tubeChanged = true;
					m_state = TubeState.open;
				}
				break;
			}
			case TubeState.closing:
			{
				if (m_transitionTimeCounter >= m_proto.openTime)
				{
					// closing finished
					m_transitionTimeCounter = 0;
					m_lastSimUpdateResults.tubeChanged = true;
					handleWireCut(null);
					m_state = TubeState.flooded;
				}
				break;
			}
			case TubeState.firing:
			{
				if (m_transitionTimeCounter >= m_proto.firingTime)
				{
					m_transitionTimeCounter = 0;
					m_lastSimUpdateResults.tubeChanged = true;
					m_state = TubeState.open;
					// firing finished, start automatic transition to dry
					if (!wireGuidanceActive && m_desiredState == TubeState.open)
						m_desiredState = TubeState.dry;
				}
				break;
			}
			case TubeState.dry:
			case TubeState.flooded:
			case TubeState.open:
				// these are stable states, we are nut supposed to be here
				assert(0, "Unexpected stable state");
		}
	}

	private void startPlayingSound(const PrerecordedSoundPrototype proto, size_t* sampleOffset = null)
	{
		if (proto is null)
			return;
		PrerecordedSoundSource currentSound = new PrerecordedSoundSource(
			m_transform, cast() proto, sampleOffset);
		m_sub.simulator.acous.registerSource(currentSound);
	}

	private void startTransitionToDesiredState()
	{
		assert(isStableState(m_state));
		assert(m_state != m_desiredState);
		switch (m_state)
		{
			case TubeState.dry:
			{
				m_state = TubeState.flooding;
				startPlayingSound(m_proto.floodSoundConfig);
				break;
			}
			case TubeState.flooded:
			{
				if (m_desiredState > TubeState.flooded)
				{
					m_state = TubeState.opening;
					startPlayingSound(m_proto.openSoundConfig);
				}
				else
				{
					m_state = TubeState.drying;
					startPlayingSound(m_proto.floodSoundConfig);
				}
				break;
			}
			case TubeState.open:
			{
				m_state = TubeState.closing;
				startPlayingSound(m_proto.openSoundConfig);
				break;
			}
			default:
				assert(0, "unsupported state");
		}
	}

	/// update transition counter and finalize state transitions
	void onPostKinematics(usecs_t dt)
	{
		if (m_desiredState == m_state)
			return;
		// check if the transition has finished
		if (isTransientState(m_state))
		{
			m_transitionTimeCounter += dt;
			updateTransientState();
		}
	}
}