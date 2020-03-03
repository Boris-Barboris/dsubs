module dsubs_server.weaponry;

import std.algorithm;
import std.array: array;

import dsubs_common.api.entities;
import dsubs_common.math;

import dsubs_sound.soundsource;
import dsubs_sound.common;
import dsubs_sound.hydrophone: IFlowNoiseMultiplier;

import dsubs_server.common;
import dsubs_server.player;
import dsubs_server.torpedo;
import dsubs_server.submarine;


struct AmmoRoomPrototype
{
	int id;
	string name;
	int capacity;
	TubeType roomType;
	bool[string] allowedWeaponSet;

	@property const(AmmoRoomTemplate) tmpl() const
	{
		AmmoRoomTemplate res = AmmoRoomTemplate(id, name);
		res.capacity = capacity;
		res.allowedWeaponSet = WeaponSet(allowedWeaponSet.keys.array);
		return res;
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
			if (wc.weaponName !in proto.allowedWeaponSet)
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


/// Server side of the tube template
struct TubePrototype
{
	TubeTemplate tmpl;
	usecs_t loadTime;
	usecs_t floodTime;
	usecs_t openTime;
	usecs_t firingTime;
	PrerecordedSoundPrototype floodSoundProto;
	PrerecordedSoundPrototype openSoundProto;
	PrerecordedSoundPrototype firingSoundProto;
	float openFlowNoiseMult = 1.0f;
}

struct TubeOperationResult
{
	bool tubeChanged;
	bool roomChanged;
}


/// Tube that launches weapons
final class Tube: IFlowNoiseMultiplier
{
	// untrusted 'initialWeapon' input
	this(Submarine owner, AmmoRoom room, const TubePrototype proto, string initialWeapon)
	{
		m_sub = owner;
		m_proto = proto;
		m_room = room;
		enforce(initialWeapon == null || initialWeapon in room.m_proto.allowedWeaponSet,
			"weapon cannot be stored in the room");
		m_loadedWeapon = m_desiredWeapon = initialWeapon;
		if (initialWeapon)
		{
			assert(m_proto.tmpl.type == TubeType.decoy);
			m_state = TubeState.open;
			m_desiredState = m_state;
		}
		m_transform = new Transform2D();
		m_transform.position = proto.tmpl.mount.mountCenter.to!vec2d;
		m_transform.rotation = proto.tmpl.mount.rotation;
		m_sub.transform.addChild(m_transform);
	}

	private
	{
		Transform2D m_transform;
		Submarine m_sub;
		AmmoRoom m_room;
		const TubePrototype m_proto;
		string m_loadedWeapon;
		string m_desiredWeapon;
		float m_pushSpeed = 10.0f;
		usecs_t m_transitionTimeCounter;

		TubeState m_state = TubeState.dry;
		TubeState m_desiredState = TubeState.dry;
		TubeOperationResult m_lastSimUpdateResults;
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
	@property string loadedWeapon() const { return m_loadedWeapon; }
	@property string desiredWeapon() const { return m_desiredWeapon; }
	@property TubeOperationResult lastSimUpdateResult() const
	{
		return m_lastSimUpdateResults;
	}

	@property TubeFullState fullState() const
	{
		return TubeFullState(
			id, m_loadedWeapon, m_desiredWeapon, m_state, m_desiredState);
	}

	TubeOperationResult processLoadRequest(string newWeaponName)
	{
		if (newWeaponName == m_desiredWeapon)
			return TubeOperationResult(false, false);
		enforce(newWeaponName == null ||
			newWeaponName in m_room.m_proto.allowedWeaponSet, "invalid weapon");
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
		Weapon w = wf.build(m_sub, weaponParams);
		w.transform.position = m_transform.wposition;
		w.transform.rotation = m_transform.wrotation;
		w.rigidBody.kinet.vel = m_sub.rigidBody.fixedPointVelocity(m_transform.wposition) +
			m_pushSpeed * m_transform.wforward;
		w.rigidBody.kinet.angVel = m_sub.rigidBody.kinet.angVel;
		w.register();
		m_desiredWeapon = m_loadedWeapon = null;
		m_state = TubeState.firing;
		size_t soundOffset = dsubs_sound.common.uniform!("[]", size_t, size_t)(0, GLOBAL_SRATE / 8);
		startPlayingSound(&m_proto.firingSoundProto, &soundOffset);
		return TubeOperationResult(true, false);
	}

	/// Creates sounds on the start of state transitions
	void onPreKinematics()
	{
		m_lastSimUpdateResults = TubeOperationResult(false, false);
		if (m_desiredState != m_state && m_transitionTimeCounter == 0)
		{
			if (isStableState(m_state))
			{
				m_lastSimUpdateResults.tubeChanged = true;
				startTransitionToDesiredState();
			}
		}
	}

	private void updateTransientState()
	{
		switch (m_state)
		{
			case TubeState.unloading:
			{
				if (m_transitionTimeCounter >= m_proto.loadTime)
				{
					// unload finished
					m_transitionTimeCounter = 0;
					assert(m_loadedWeapon);
					m_room.putWeapon(m_loadedWeapon);
					m_lastSimUpdateResults = TubeOperationResult(true, true);
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
					m_state = TubeState.flooded;
				}
				break;
			}
			case TubeState.firing:
			{
				if (m_transitionTimeCounter >= m_proto.firingTime)
				{
					// firing finished, start automatic transition to dry
					m_transitionTimeCounter = 0;
					m_lastSimUpdateResults.tubeChanged = true;
					m_state = TubeState.open;
					m_desiredState = TubeState.dry;
				}
				break;
			}
			default:
				assert(0, "unhandled state");
		}
	}

	private void startPlayingSound(const(PrerecordedSoundPrototype)* proto, size_t* sampleOffset = null)
	{
		if (proto is null || proto.tds is null)
			return;
		PrerecordedSoundSource currentSound = new PrerecordedSoundSource(
			new Transform2D(m_transform.wposition), cast() *proto, sampleOffset);
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
				startPlayingSound(&m_proto.floodSoundProto);
				break;
			}
			case TubeState.flooded:
			{
				if (m_desiredState > TubeState.flooded)
				{
					m_state = TubeState.opening;
					startPlayingSound(&m_proto.openSoundProto);
				}
				else
				{
					m_state = TubeState.drying;
					startPlayingSound(&m_proto.floodSoundProto);
				}
				break;
			}
			case TubeState.open:
			{
				m_state = TubeState.closing;
				startPlayingSound(&m_proto.openSoundProto);
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
		m_transitionTimeCounter += dt;
		// check if the transition has finished
		if (isTransientState(m_state))
			updateTransientState();
	}
}