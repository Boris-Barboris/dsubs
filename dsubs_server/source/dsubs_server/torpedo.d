module dsubs_server.torpedo;

import std.array: array;
import std.algorithm: map, max, min, remove, SwapStrategy, filter;
import std.algorithm.searching: minElement;
import std.algorithm.sorting: sort;
import std.parallelism: task;

import core.bitop: popcnt;

import dsubs_common.containers.array;
import dsubs_common.api.constants;
import dsubs_common.api.entities;
import dsubs_common.math;
import dsubs_common.event;

import dsubs_sound.activesonar;
import dsubs_sound.hydrophone;
import dsubs_sound.soundsource;
import dsubs_sound.common: uniform, GLOBAL_SRATE;

import dsubs_server.common;
import dsubs_server.vessel;
import dsubs_server.dynamics;
import dsubs_server.propulsion;
import dsubs_server.simulator;
import dsubs_server.player: Captain;
import dsubs_server.weaponry;
import dsubs_server.submarine: Submarine;




interface IGuidance
{
	void update(usecs_t dt);

	void setUnassignedParams();

	void shutdown();

	void updateParamsByWire(WeaponParamValue[] params);

	void activateByWire(bool shouldBeActive);

	WireGuidanceFullState getFullState(bool includeWeaponParams);
}


abstract class Weapon: Vessel
{
	protected
	{
		Submarine m_shooter;
		Tube m_shooterTube;
		Captain m_shooterCaptain;
		IGuidance m_guidance;
	}

	final @property Submarine shooter() { return m_shooter; }
	final @property Tube shooterTube() { return m_shooterTube; }
	final @property Captain shooterCaptain() { return m_shooterCaptain; }
	@property IGuidance guidance() { return m_guidance; }

	// all detonated weapons will be unregistered by weapons
	// component during updateGuidances().
	@property bool detonated() const;

	this(Submarine shooter, string templateName, Tube tube)
	{
		super(templateName);
		m_shooter = shooter;
		if (m_shooter)
			m_shooterCaptain = shooter.captain;
		m_shooterTube = tube;
	}

	override void register(Simulator sim)
	{
		super.register(sim);
		m_guidance.setUnassignedParams();
		simulator.weapons.registerEntity(this);
	}

	override protected void onFirstKill()
	{
		// cut the wire
		if (m_shooterTube)
			m_shooterTube.handleWireCut(this);
	}

	override void shutdown()
	{
		super.shutdown();
		m_guidance.shutdown();
		onFirstKill();
		simulator.weapons.unregisterEntity(this);
	}
}


final class StaticDecoy: Weapon
{
	this(Submarine shooter, string templateName, Tube tube, IGuidance guidance)
	{
		super(shooter, templateName, tube);
		m_guidance = guidance;
	}

	override @property bool detonated() const { return false; }
}


class StaticDecoyGuidance: IGuidance
{
	protected
	{
		StaticDecoy m_decoy;
		bool m_active;
		usecs_t m_activateAfter;
		float m_fuelLeft;
	}

	void update(usecs_t dt)
	{
		if (!m_active)
		{
			m_activateAfter -= dt;
			if (m_activateAfter <= 0)
			{
				m_active = true;
				onActivate();
			}
		}
		else
		{
			m_fuelLeft -= dt / 1e6;
			if (m_fuelLeft < 0.0f)
			{
				m_decoy.kill("fuel exhausted", null);
				shutdown();
			}
		}
	}

	protected abstract void onActivate();

	void setUnassignedParams() {}

	void updateParamsByWire(WeaponParamValue[] params)
	{
		throw new Exception("Decoys cannot be wire-guided");
	}

	void activateByWire(bool shouldBeActive)
	{
		throw new Exception("Decoys cannot be wire-guided");
	}

	WireGuidanceFullState getFullState(bool includeWeaponParams)
	{
		throw new Exception("Decoys cannot be wire-guided");
	}

	void shutdown() {}
}


final class ActiveDecoyGuidance: StaticDecoyGuidance
{
	private
	{
		ReflectorPrototype m_activeReflectorProto;
		Reflector m_activeReflector;
	}

	protected override void onActivate()
	{
		m_activeReflector = new Reflector(
			m_decoy.transform, m_activeReflectorProto);
		m_decoy.simulator.acous.registerReflector(m_activeReflector);
	}

	override void shutdown()
	{
		if (m_activeReflector)
		{
			m_decoy.simulator.acous.unregisterReflector(m_activeReflector);
			m_activeReflector = null;
		}
	}
}


final class PassiveDecoyGuidance: StaticDecoyGuidance
{
	protected override void onActivate()
	{
		m_decoy.targetThrottle = uniform(0.8f, 1.0f);
	}
}


/// Server-side torpedo model
final class Torpedo: Weapon
{
	private
	{
		Hydrophone m_hydrophone;
		ActiveSonar m_sonar;
		bool m_detonated;
	}

	@property inout(Hydrophone) hydrophone() inout { return m_hydrophone; }
	@property ActiveSonar sonar() { return m_sonar; }
	override @property TorpedoGuidance guidance()
	{
		return cast(TorpedoGuidance) m_guidance;
	}
	override @property bool detonated() const { return m_detonated; }

	@property inout(TorpedoFactory) factory() inout
	{
		return cast (inout(TorpedoFactory))
			Globals.entityDb.getWeaponFactory(prototypeName);
	}

	this(Submarine shooter, string templateName, Tube tube)
	{
		super(shooter, templateName, tube);
		m_guidance = new TorpedoGuidance(this);
	}

	override void register(Simulator sim)
	{
		super.register(sim);
		guidance.m_lastPos = transform.position;
		if (m_hydrophone)
			simulator.acous.registerHydrophone(m_hydrophone);
		if (m_sonar)
		{
			m_sonar.active = true;
			simulator.acous.registerSonar(m_sonar);
		}
	}

	override void shutdown()
	{
		super.shutdown();
		if (m_hydrophone)
		{
			simulator.acous.unregisterHydrophone(m_hydrophone);
			m_hydrophone.release();
		}
		if (m_sonar)
		{
			simulator.acous.unregisterSonar(m_sonar);
			m_sonar.release();
		}
	}

	override bool kill(string cause, Captain killer)
	{
		bool res = super.kill(cause, killer);
		if (res)
		{
			if (m_hydrophone)
				m_hydrophone.canBeActive = false;
			if (m_sonar)
				m_sonar.active = false;
		}
		return res;
	}
}


/// Torpedo guidance, detonation and fuel controller. Is too bloated and
/// should be split, but who cares.
final class TorpedoGuidance: IGuidance
{
	private
	{
		Torpedo m_torpedo;
		WeaponSensorMode m_sensorMode;
		WeaponSearchPattern m_searchPattern;
		const(ReflectorPrototype)* m_activeReflectorProto;
		Reflector m_activeReflector;
		float m_marchCourse;
		float m_marchSpeed;
		float m_activeSpeed;
		float m_marchThrottle = 1.0f;
		float m_activeThrottle = 1.0f;
		float m_fuelLeft;
		float m_fuelEffExponent = 2.0f;
		float m_distanceTraveled = 0.0f;
		float m_activationRange;
		float m_minActivationRange;
		vec2d m_lastPos;
		bool m_activated;

		// set to true when at least once activation
		// command was issued by wire. Disables
		// range-based activation
		bool m_wireGuidedActivationControl;

		// snake-related parameters
		float m_snakeArm;
		float m_snakeAngle = dgr2rad(45);
		float m_snakeArmBeforeTurn;
		float m_snakeSign = 1.0f;

		// spiral-related parameters
		float m_spiralStartTarget = 1.0f;
		float m_spiralTargetRedPerRange;
		float m_spiralSinceStart = 0.0f;

		// course is leading with this integral gain relative to target ang vel
		float m_trackAngVelKi = 0.0f;
		float m_trackAngVelAccumul = 0.0f;

		// detonator parameters
		// 150 meters should be enough to tackle 1-second main integration
		// step crudeness.
		float m_detonationSearchRadius = 150.0f;
		float m_detonationMassK = 4.5f;
		float m_blastRadius = 70.0f;
		PrerecordedSoundPrototype m_detonationSoundProto;
	}

	@property void fuelLeft(float rhs) { m_fuelLeft = rhs; }

	@property float distanceTraveled() const { return m_distanceTraveled; }

	@property Torpedo torpedo() { return m_torpedo; }

	@property bool activated() const { return m_activated; }

	private this(Torpedo owner)
	{
		m_torpedo = owner;
		m_pingTdsOffset = uniform(0, GLOBAL_SRATE - 1);
	}

	void shutdown()
	{
		if (m_activeReflector)
			m_torpedo.simulator.acous.unregisterReflector(m_activeReflector);
	}

	/// verify some variables that could have been missed for some reason
	void setUnassignedParams()
	{
		// dumbfire snapshot in straight direction
		if (isNaN(m_marchCourse))
			m_marchCourse = m_torpedo.transform.wrotation;
	}

	/// Estimate of range left at current throttle
	float rangeEstimate() const
	{
		float throttle = m_torpedo.propulsors[0].throttle.fabs;
		float fuelConsumptionRate = pow(throttle, m_fuelEffExponent);
		float timeLeft = m_fuelLeft / fuelConsumptionRate;
		if (!isNormal(timeLeft))
			return 0.0f;
		return timeLeft * speedForThrottle(m_torpedo, throttle);
	}

	private void activate()
	{
		if (m_activated)
			return;
		// wire re-activation should reset spiral size
		m_spiralSinceStart = 0.0f;
		m_activated = true;
		if (m_activeReflectorProto && m_activeReflector is null)
		{
			// add new torpedo's reflector
			m_activeReflector = new Reflector(m_torpedo.transform,
				*m_activeReflectorProto);
		}
		if (m_activeReflector)
			m_torpedo.simulator.acous.registerReflector(m_activeReflector);
	}

	private void deactivate()
	{
		if (!m_activated)
			return;
		m_activated = false;
		m_targetTracked = false;
		if (m_activeReflector)
			m_torpedo.simulator.acous.unregisterReflector(m_activeReflector);
	}

	void update(usecs_t dt)
	{
		// perform fuel-related calculations
		assert(m_torpedo.propulsors.length == 1);
		float fuelSpent = pow(m_torpedo.propulsors[0].throttle.fabs, m_fuelEffExponent);
		m_fuelLeft -= fuelSpent;
		if (m_fuelLeft < 0.0f)
		{
			m_torpedo.kill("fuel exhausted", null);
			if (m_activeReflector)
			{
				m_torpedo.simulator.acous.unregisterReflector(m_activeReflector);
				m_activeReflector = null;
			}
			return;
		}
		// if wire was cut, disable wire-guided activation override
		if (m_torpedo.shooterTube)
			if (m_torpedo.shooterTube.wireGuidedWeapon !is m_torpedo)
				m_wireGuidedActivationControl = false;
		// activation by range logic
		float distanceAdded = (m_lastPos - m_torpedo.transform.wposition).length;
		m_distanceTraveled += distanceAdded;
		m_lastPos = m_torpedo.transform.wposition;
		if (!m_activated && !m_wireGuidedActivationControl &&
			m_distanceTraveled >= m_activationRange)
		{
			m_snakeArmBeforeTurn += m_snakeArm;
			activate();
		}
		// assign course and throttle based on activation state
		if (m_activated)
		{
			// first we check if we should detonate.
			if (m_distanceTraveled > 300.0f)	// self-explosion protection
			{
				RigidBody[] inSearchRadius = m_torpedo.simulator.phys.
					findRigidBodiesInCirlce(
						m_torpedo.transform.wposition.to!vec2f,
						m_detonationSearchRadius);
				removeFirstUnstable(inSearchRadius, m_torpedo.rigidBody);
				if (inSearchRadius.length > 0)
				{
					if (detonateIfNeeded(inSearchRadius))
						return;	// boom!
				}
			}
			handleSensors(dt);
			if (!m_targetTracked)
			{
				// no target is sight
				m_trackAngVelAccumul = 0.0f;
				m_torpedo.targetThrottle = m_activeThrottle;
				final switch (m_searchPattern)
				{
					case WeaponSearchPattern.straight:
						m_torpedo.rudder.directMode = false;
						m_torpedo.targetCourse = m_marchCourse;
						break;
					case WeaponSearchPattern.spiral:
						m_spiralSinceStart += distanceAdded;
						m_torpedo.rudder.directMode = true;
						m_torpedo.rudder.directRudderPos = m_spiralStartTarget /
							(1.0f + m_spiralTargetRedPerRange * sqrt(m_spiralSinceStart));
						break;
					case WeaponSearchPattern.snake:
						m_snakeArmBeforeTurn -= distanceAdded;
						if (m_snakeArmBeforeTurn < 0.0f)
						{
							// snake turn
							m_snakeArmBeforeTurn = 2.0f * m_snakeArm;
							m_snakeSign = -m_snakeSign;
						}
						m_torpedo.rudder.directMode = false;
						m_torpedo.targetCourse = m_marchCourse +
							m_snakeSign * m_snakeAngle;
						break;
				}
			}
			else
			{
				// homing mode
				assert(m_sensorMode != WeaponSensorMode.dumb);
				m_torpedo.rudder.directMode = false;
				m_torpedo.targetThrottle = m_activeThrottle;
				if (!isNaN(m_curTargetAngVel))
				{
					m_trackAngVelAccumul += m_curTargetAngVel;
					float accumulLimit = dgr2rad(50) / m_trackAngVelKi;
					m_trackAngVelAccumul = clamp(m_trackAngVelAccumul,
						-accumulLimit, accumulLimit);
					m_torpedo.targetCourse = m_curTargetDir +
						m_trackAngVelAccumul * m_trackAngVelKi;
				}
				else
					m_torpedo.targetCourse = m_curTargetDir;
			}
		}
		else
		{
			m_torpedo.rudder.directMode = false;
			m_torpedo.targetThrottle = m_marchThrottle;
			m_torpedo.targetCourse = m_marchCourse;
		}
	}

	void updateParamsByWire(WeaponParamValue[] params)
	{
		const TorpedoFactory factory = m_torpedo.factory;
		foreach (const WeaponParamValue param; params)
		{
			enforce(popcnt(param.type) == 1, "must choose one parameter to set");
			enforce(param.type & factory.m_wireControlledParams, "parameter " ~
				param.type.to!string ~ " cannot be changed via wire");
			switch (param.type)
			{
				case WeaponParamType.course:
					m_marchCourse = param.course.validateFloat.clampAngle;
					break;
				case WeaponParamType.sensorMode:
					enforce(factory.sensorModes & param.sensorMode,
						"invalid sensor mode");
					enforce(popcnt(param.sensorMode) <= 1, "must choose at most one");
					if (m_sensorMode != param.sensorMode)
					{
						// reset tracking
						m_targetTracked = false;
						// windup sonar ping slices
						if (m_sensorMode == WeaponSensorMode.active)
						{
							ActiveSonar sonar = m_torpedo.m_sonar;
							assert(sonar !is null);
							while (sonar.canGenerateSlice)
								sonar.skipSiceGeneration();
						}
						// deactivate hydrophone
						if (m_sensorMode == WeaponSensorMode.passive)
						{
							Hydrophone h = m_torpedo.m_hydrophone;
							assert(h !is null);
							h.shouldBeActive = false;
						}
						m_sensorMode = param.sensorMode;
					}
					break;
				case WeaponParamType.searchPattern:
					enforce(factory.searchPatterns.availablePatterns & param.searchPattern,
						"invalid search pattern");
					enforce(popcnt(param.searchPattern) == 1, "must choose one");
					m_searchPattern = param.searchPattern;
					break;
				case WeaponParamType.marchSpeed:
					enforce(factory.marchSpeedRange.contains(param.speed), "invalid marchSpeed");
					m_marchSpeed = param.speed;
					m_marchThrottle = throttleForSpeed(m_torpedo, m_marchSpeed);
					assert(isNormal(m_marchThrottle));
					break;
				case WeaponParamType.activeSpeed:
					enforce(factory.activeSpeedRange.contains(param.speed), "invalid activeSpeed");
					m_activeSpeed = param.speed;
					m_activeThrottle = throttleForSpeed(m_torpedo, m_activeSpeed);
					assert(isNormal(m_activeThrottle));
					break;
				default:
					throw new Exception("unacceptable weapon parameter");
			}
		}
	}

	void activateByWire(bool shouldBeActive)
	{
		m_wireGuidedActivationControl = true;
		if (!m_activated && shouldBeActive)
		{
			if (m_distanceTraveled < m_minActivationRange)
				return;
			activate();
		}
		else if (m_activated && !shouldBeActive)
		{
			deactivate();
		}
	}

	WireGuidanceFullState getFullState(bool includeWeaponParams)
	{
		assert(m_torpedo.shooterTube);
		WireGuidanceFullState res;
		res.wireGuidanceId = m_torpedo.id.toString;
		res.tubeId = m_torpedo.shooterTube.id;
		res.rangeLeft = rangeEstimate();
		res.weaponSnap = m_torpedo.kinematicSnapshot;
		res.active = m_activated;
		res.tracking = m_activated ? m_targetTracked : false;
		if (res.tracking)
			res.trackingDir = m_curTargetDir;
		if (!includeWeaponParams)
			return res;
		// dump weapon params
		res.weaponParams.reserve(6);
		res.weaponParams ~= WeaponParamValue(WeaponParamType.course);
		res.weaponParams[$-1].course = m_marchCourse;
		res.weaponParams ~= WeaponParamValue(WeaponParamType.activeSpeed);
		res.weaponParams[$-1].speed = m_activeSpeed;
		res.weaponParams ~= WeaponParamValue(WeaponParamType.marchSpeed);
		res.weaponParams[$-1].speed = m_marchSpeed;
		res.weaponParams ~= WeaponParamValue(WeaponParamType.activationRange);
		res.weaponParams[$-1].range = m_activationRange;
		res.weaponParams ~= WeaponParamValue(WeaponParamType.searchPattern);
		res.weaponParams[$-1].searchPattern = m_searchPattern;
		res.weaponParams ~= WeaponParamValue(WeaponParamType.sensorMode);
		res.weaponParams[$-1].sensorMode = m_sensorMode;
		return res;
	}

	private
	{
		usecs_t m_sinceLastPing;
		size_t m_pingTdsOffset;
		int m_pingIntervalSearch;
		SonarPing m_currentPing;
		ubyte[] m_sonarImage;
		size_t m_sliceByteSize;
	}

	private struct Approach
	{
		double closestApproachDistance = double.max;
		double closestApproachTime = 0.0;	// clamped to [0; 1]
		bool runningAway;	// if theoretical closest approach t is in (-inf; 1]
	}

	private static Approach getClosestApproach(vec2d guidancePos, vec2d guidanceVel,
		RigidBody targetBody)
	{
		// go 1 second in the past (assume straight movement)
		vec2d guiPos0 = guidancePos - guidanceVel;
		vec2d tgtPos0 = targetBody.kinet.pos - targetBody.kinet.vel;
		// relative velocity of target as if guidance was stationary
		vec2d tgtRelVel = targetBody.kinet.vel - guidanceVel;
		// https://stackoverflow.com/a/1501725
		double l2 = tgtRelVel.squaredLength;
		if (fabs(l2) < 1e-6)
		{
			Approach res;
			res.closestApproachDistance = (guiPos0 - tgtPos0).length;
			res.closestApproachTime = 0;
			res.runningAway = true;
			return res;
		}
		Approach res;
		double t = dot(guiPos0 - tgtPos0, tgtRelVel) / l2;
		if (t <= 1.0)
			res.runningAway = true;
		res.closestApproachTime = fmax(0.0, fmin(1.0, t));
		vec2d projection = tgtPos0 + res.closestApproachTime * tgtRelVel;
		res.closestApproachDistance = (projection - guiPos0).length;
		return res;
	}

	// detonation logic tries to detonate as late as possible
	private bool detonateIfNeeded(RigidBody[] closeBodies)
	{
		bool shouldDetonate;
		// [0; 1]. 1 is now, 0 is 1 second ago
		double detonationTime = double.max;

		// first pass decides whether we should detonate, and if we do,
		// when and where. Earliest detonation wins.
		foreach (RigidBody rb; closeBodies)
		{
			// Since we are running guidance at 1Hz rate, fast torpedoes may
			// miss small or fast-moving targets. We need to get the closest approach
			// distance between two trajectory sections instead of simple distance
			// between the 2 rigid bodies in order to decide wether we detonate or not.

			double triggerDist = pow(rb.mass, 1.0f / 3) * m_detonationMassK;
			Approach approach = getClosestApproach(m_torpedo.transform.wposition,
				m_torpedo.rigidBody.kinet.vel, rb);
			double dist = approach.closestApproachDistance;
			if (triggerDist >= dist)
			{
				// detonator is armed
				if (approach.runningAway || m_fuelLeft < 1.5f)
				{
					// we must explode
					shouldDetonate = true;
					// update detonation time
					if (approach.closestApproachTime < detonationTime)
						detonationTime = approach.closestApproachTime;
				}
			}
		}

		if (!shouldDetonate)
			return false;

		vec2d explosionCenter = m_torpedo.transform.wposition -
			(1.0 - detonationTime) * m_torpedo.rigidBody.kinet.vel;

		// second pass we choose who to kill
		Killable[] inKillRadius;
		foreach (RigidBody rb; closeBodies)
		{
			vec2d rbPosAtExplosionTime = rb.transform.wposition -
				(1.0 - detonationTime) * rb.kinet.vel;
			double dist = (explosionCenter - rbPosAtExplosionTime).length;
			if (rb.owner && dist <= m_blastRadius)
				inKillRadius ~= rb.owner;
		}
		detonate(inKillRadius, explosionCenter);
		return true;
	}

	bool getKillRecordForKillable(Killable k, out KillRecord res)
	{
		if (m_torpedo.shooter is null)
			return false;
		Vessel v = cast(Vessel) k;
		if (v is null)
			return false;
		res.relation = m_torpedo.shooter.relationWith(v);
		res.vesselType = v.prototypeName;
		res.weaponType = m_torpedo.prototypeName;
		Submarine sub = cast(Submarine) k;
		if (sub && sub.captain)
			res.submarineCaptain = sub.captain.name;
		return true;
	}

	private void detonate(Killable[] inKillRadius, vec2d explosionCenter)
	{
		trace("Torpedo detonated!!!");
		m_torpedo.m_detonated = true;
		foreach (v; inKillRadius)
		{
			string killNote = "Killed" ~
				(m_torpedo.m_shooterCaptain ?
					" by " ~ m_torpedo.m_shooterCaptain.name : "") ~
				" with " ~ m_torpedo.prototypeName ~ " weapon";
			bool isActuallyKilled = v.kill(killNote, m_torpedo.m_shooterCaptain);
			if (isActuallyKilled)
			{
				trace(v, " is killed in explosion");
				// add kill record to the shooter submarine
				KillRecord record;
				if (getKillRecordForKillable(v, record))
					m_torpedo.shooter.addKillRecord(record);
				if (Globals.database)
				{
					void reportFunc(Killable killedVessel)
					{
						try
						{
							Globals.database.insertKillRecord(
								m_torpedo.shooterCaptain,
								m_torpedo.shooter,
								killedVessel, m_torpedo);
						}
						catch (Exception ex)
						{
							error("error during kill report: ", ex.toString);
						}
					}
					Globals.auxTaskPool.put(task(
						((Killable vv) => { reportFunc(vv); })(v)
						));
				}
			}
			else
				trace(v, " is in explosion radius");
		}
		m_torpedo.kill("detonation", null);
		SoundSource detonationSoundSource = new PrerecordedSoundSource(
			new Transform2D(explosionCenter),
			m_detonationSoundProto, null);
		m_torpedo.simulator.acous.registerSource(detonationSoundSource);
	}

	Event!(void delegate(ubyte[] image, int w, int h)) onSonarImageReady;
	Event!(void delegate(const(ushort)[] bbData)) onHydrophoneSliceReady;

	/// process sensor signals.
	private void handleSensors(usecs_t dt)
	{
		switch (m_sensorMode)
		{
			case WeaponSensorMode.dumb:
				return;

			case WeaponSensorMode.active:
			{
				ActiveSonar sonar = m_torpedo.m_sonar;
				assert(sonar !is null);
				if (sonar.hasSliceToSend)
				{
					// we need to process new slice data from active ping
					int sliceId = sonar.readySliceId;
					size_t idxStart = (sonar.secDur - 1 - sliceId) * m_sliceByteSize;
					size_t idxEnd = idxStart + m_sliceByteSize;
					m_sonarImage[idxStart .. idxEnd] = sonar.getLastSlice();
					sonar.markSliceSent();
					processSonarSlice(m_sonarImage[idxStart .. idxEnd], sliceId);
					if (!sonar.canGenerateSlice)
					{
						// image is finished
						if (m_targetTracked && m_targetPingId < sonar.pingCounter)
						{
							// we've lost the target
							m_targetTracked = false;
						}
						onSonarImageReady(m_sonarImage,
							sonar.proto.getSliceXResol(),
							sonar.proto.radialRes * (sliceId + 1));
					}
				}
				if (m_sinceLastPing == 0)
				{
					// we may wish a more frequent ping when the tracked target is close
					if (m_targetTracked)
						sonar.secDur = 1 + m_targetSliceId;
					else
						sonar.secDur = sonar.maxSec;
					m_currentPing = sonar.startPing(
						sonar.proto.maxPeakIlevel, &m_pingTdsOffset);
					assert(m_currentPing);
					m_torpedo.simulator.acous.registerSource(m_currentPing);
					m_sliceByteSize =
						sonar.proto.getSliceXResol() * sonar.proto.radialRes;
					m_sonarImage.length = m_sliceByteSize * sonar.secDur;
				}
				m_sinceLastPing += dt;
				if (m_sinceLastPing >= m_pingIntervalSearch * 1_000_000)
					m_sinceLastPing = 0;
				if (m_targetTracked && m_sinceLastPing >= max(3, sonar.secDur) * 1_000_000)
					m_sinceLastPing = 0;
				break;
			}

			case WeaponSensorMode.passive:
			{
				Hydrophone h = m_torpedo.m_hydrophone;
				assert(h !is null);
				assert(h.antennaCount == 1);
				bool wasActive = h.active;
				h.shouldBeActive = true;
				if (!wasActive)
				{
					// hydrophone will only start generating data on the next
					// simulation step after activation.
					return;
				}
				ushort[] broadbandData = h.getBroadbandData(0);
				onHydrophoneSliceReady(broadbandData);
				processHydrophoneData(broadbandData);
				break;
			}

			default:
				assert(0, "not implemented");
		}
	}

	private
	{
		bool m_targetTracked;
		int m_targetPingId = -1;
		int m_targetSliceId = -1;
		double m_prevTargetDir;
		double m_curTargetDir;
		double m_curTargetAngVel;
		usecs_t m_prevTargetTime;

		// detection margins
		int m_sonarNoiseMargin;
		int m_hydrophoneNoiseMargin;
	}

	/// look for targets in the sonar slice
	private void processSonarSlice(const(ubyte)[] slice, int sliceId)
	{
		ActiveSonar sonar = m_torpedo.m_sonar;
		if (m_targetTracked && m_targetPingId >= sonar.pingCounter)
		{
			// we are tracking, nothing to do
			return;
		}
		int width = sonar.proto.getSliceXResol();
		int height = sonar.proto.radialRes;
		int[] peakColumns = findPeaks(slice, width, height, m_sonarNoiseMargin);
		// trace("found peaks: ", peakColumns);
		if (peakColumns.length == 0)
			return;
		if (!m_targetTracked)
		{
			// let's select random peak as target
			m_targetTracked = true;
			m_prevTargetDir = double.nan;
			m_curTargetAngVel = double.nan;
			m_prevTargetTime = m_torpedo.simulator.worldTime;
			m_targetPingId = sonar.pingCounter;
			m_targetSliceId = sliceId;
			m_curTargetDir = sonarColumnToRotation(
				peakColumns[uniform!"[)"(0, peakColumns.length)], width);
		}
		else
		{
			// find the peak in this slice that is closest to currently tracked target
			m_prevTargetDir = m_curTargetDir;
			m_targetPingId = sonar.pingCounter;
			m_targetSliceId = sliceId;
			double[] sliceTargetWrots = peakColumns.map!(
				pc => sonarColumnToRotation(pc, width)).array();
			sliceTargetWrots.sort!(
				(a, b) =>
					angleDist(a, m_prevTargetDir).fabs <
					angleDist(b, m_prevTargetDir).fabs)();
			m_curTargetDir = sliceTargetWrots[0];
			m_curTargetAngVel = angleDist(m_curTargetDir, m_prevTargetDir) * 1e6 /
				(m_torpedo.simulator.worldTime - m_prevTargetTime);
			m_prevTargetTime = m_torpedo.simulator.worldTime;
		}
	}

	double sonarColumnToRotation(int col, int width)
	{
		return clampAngle(m_torpedo.sonar.transform.wrotation +
			dgr2rad(m_torpedo.sonar.proto.span / 2) -
			(col + 0.5f) / width * dgr2rad(m_torpedo.sonar.proto.span));
	}

	/// look for targets in the broadband data slice
	private void processHydrophoneData(const(ushort)[] slice)
	{
		Hydrophone h = m_torpedo.m_hydrophone;
		int width = slice.length.to!int;
		int[] peakColumns = findPeaks(slice, width, 1, m_hydrophoneNoiseMargin);
		// trace("found peaks: ", peakColumns);
		if (peakColumns.length == 0)
		{
			m_targetTracked = false;
			return;
		}
		if (!m_targetTracked)
		{
			// let's select random peak as target
			m_targetTracked = true;
			m_prevTargetDir = double.nan;
			m_curTargetAngVel = double.nan;
			m_prevTargetTime = m_torpedo.simulator.worldTime;
			m_curTargetDir = hydrphoneColumnToRotation(
				peakColumns[uniform!"[)"(0, peakColumns.length)]);
		}
		else
		{
			// find the peak in this slice that is closest to currently tracked target
			m_prevTargetDir = m_curTargetDir;
			double[] sliceTargetWrots = peakColumns.map!(
				pc => hydrphoneColumnToRotation(pc)).array();
			sliceTargetWrots.sort!(
				(a, b) =>
					angleDist(a, m_prevTargetDir).fabs <
					angleDist(b, m_prevTargetDir).fabs)();
			m_curTargetDir = sliceTargetWrots[0];
			m_curTargetAngVel = angleDist(m_curTargetDir, m_prevTargetDir) * 1e6 /
				(m_torpedo.simulator.worldTime - m_prevTargetTime);
			m_prevTargetTime = m_torpedo.simulator.worldTime;
		}
	}

	double hydrphoneColumnToRotation(int col)
	{
		Hydrophone h = m_torpedo.hydrophone;
		return clampAngle(h.transform.wrotation + h.span / 2 -
			(col + 0.5f) / h.beamCount * h.span);
	}

	static int[] findPeaks(T)(const(T)[] image, int width, int height, int noiseCutoff)
	{
		int minimum = minElement(image);
		int detectionLevel = minimum + noiseCutoff;
		static int[] rowSums;
		rowSums.length = width;
		rowSums[] = 0;

		// we accumulate energy across all rows of the slice
		for (int row = 0; row < height; row++)
		{
			for (int col = 0; col < width; col++)
			{
				int overLevel = image[col + row * width] - detectionLevel;
				if (overLevel > 0)
					rowSums[col] += overLevel;
			}
		}

		int[] peakColumns;

		for (int col = 0; col < width; col++)
		{
			if (rowSums[col] <= 0)
				continue;
			// peak candidate
			if (col == 0 && rowSums[1] < rowSums[col] ||
				col == width - 1 && rowSums[col - 1] <= rowSums[col] ||
				col > 0 && col < width - 1 && rowSums[col] >= rowSums[col - 1]
					&& rowSums[col] > rowSums[col + 1])
			{
				// actual peak
				peakColumns ~= col;
			}
		}

		// sort peakColumns to place brightest first
		peakColumns.sort!((x, y) => rowSums[x] > rowSums[y]);

		return peakColumns;
	}
}


final class WeaponCollection
{
	private
	{
		Weapon[] m_entities;
	}

	@property Weapon[] entities() { return m_entities; }

	void registerEntity(Weapon e)
	{
		synchronized(this)
		{
			m_entities ~= e;
		}
	}

	void unregisterEntity(Weapon e)
	{
		synchronized(this)
		{
			removeFirstUnstable(m_entities, e);
		}
	}

	void shutdownAll()
	{
		Weapon[] weaponsToRemove = m_entities.dup;
		foreach (w; weaponsToRemove)
			w.shutdown();
		assert(m_entities.length == 0, "weapons leak");
	}

	void clean()
	{
		m_entities.length = 0;
	}

	void updateGuidances(usecs_t dt)
	{
		foreach (Weapon weapon; Globals.taskPool.parallel(m_entities, 1))
			if (!weapon.dead)
				weapon.guidance.update(dt);
		// remove all detonated torpedoes
		Weapon[] detonatedEntities = m_entities.filter!(t => t.detonated).array;
		foreach (w; detonatedEntities)
			w.shutdown();
	}
}



abstract class WeaponFactory: VesselFactory
{
	string name;
	string description;
	bool marchCourseConfigurable;
	bool playable;
	bool wireGuided;

	@property const(WeaponTemplate) tmpl() const
	{
		assert(m_paramDescsGenerated);
		return const WeaponTemplate(
			name, description, turningRadius, m_availableParams, m_paramDescs,
			fuel.mean, fullThrottleSpd, fuelEffExponent, wireGuided,
			m_wireControlledParams);
	}

	float turningRadius = 0.0f;
	RolledF fuel;
	/// balancing parameter. Enter real max speed. Drag Cd1 will be tuned with respect to propulsor
	/// to match this value.
	float fullThrottleSpd = 0.0f;
	float fuelEffExponent = 2.0f;

	protected
	{
		bool m_paramDescsGenerated;
		WeaponParamType m_availableParams;
		WeaponParamType m_wireControlledParams;
		WeaponParamDesc[] m_paramDescs;
	}

	// inlined weapon parameter descriptions. They should not be assigned directly, but
	MinMax marchSpeedRange;
	MinMax activeSpeedRange;
	MinMax activationRange;
	WeaponSensorMode sensorModes;
	WeaponParamDescSearchPatterns searchPatterns;
	/// Sensor mode that is chosen if client does not explicitly set the mode.
	WeaponSensorMode defaultSensorMode;
	WeaponSearchPattern defaultSearchPattern = WeaponSearchPattern.straight;

	/// Process allparameters and generate m_availableParams and m_paramDescs.
	void generateParamDescs()
	{
		m_availableParams = WeaponParamType.none;
		m_paramDescs.length = 0;
		if (marchCourseConfigurable)
			m_availableParams |= WeaponParamType.course;
		//if (marchSpeedRange.max > marchSpeedRange.min)
		{
			m_availableParams |= WeaponParamType.marchSpeed;
			WeaponParamDesc pd;
			pd.type = WeaponParamType.marchSpeed;
			pd.speedRange = marchSpeedRange;
			m_paramDescs ~= pd;
		}
		//if (activeSpeedRange.max > activeSpeedRange.min)
		{
			m_availableParams |= WeaponParamType.activeSpeed;
			WeaponParamDesc pd;
			pd.type = WeaponParamType.activeSpeed;
			pd.speedRange = activeSpeedRange;
			m_paramDescs ~= pd;
		}
		//if (activationRange.max > activationRange.min)
		{
			m_availableParams |= WeaponParamType.activationRange;
			WeaponParamDesc pd;
			pd.type = WeaponParamType.activationRange;
			pd.activationRange = activationRange;
			m_paramDescs ~= pd;
		}
		if (popcnt(sensorModes))
		{
			m_availableParams |= WeaponParamType.sensorMode;
			WeaponParamDesc pd;
			pd.type = WeaponParamType.sensorMode;
			pd.sensorModes = sensorModes;
			m_paramDescs ~= pd;
		}
		if (popcnt(searchPatterns.availablePatterns))
		{
			m_availableParams |= WeaponParamType.searchPattern;
			WeaponParamDesc pd;
			pd.type = WeaponParamType.searchPattern;
			pd.searchPatterns = searchPatterns;
			m_paramDescs ~= pd;
		}
		if (wireGuided)
		{
			// for now, all parameters can be changed after launch,
			// except activationRange.
			m_wireControlledParams = cast(WeaponParamType) (m_availableParams &
				~cast(int)(WeaponParamType.activationRange));
		}
		m_paramDescsGenerated = true;
	}

	Weapon build(Submarine shooter, const(WeaponParamValue)[] launchParams,
		Tube tube) const;
}


final class ActiveDecoyFactory: WeaponFactory
{
	ReflectorPrototype activeReflectorProto =
		ReflectorPrototype(vec2f(30, 30), [-7.0f, -7.0f, -7.0f]);
	usecs_t activateAfter = 4_000_000;

	/// Verify launch params, build torpedo entity and assign launch params to guidance
	override StaticDecoy build(Submarine shooter,
		const(WeaponParamValue)[] launchParams, Tube tube) const
	{
		enforce(launchParams.length == 0, "decoy is not configurable");
		ActiveDecoyGuidance guidance = new ActiveDecoyGuidance();
		StaticDecoy res = new StaticDecoy(shooter, name, tube, guidance);
		super.bootstrap(res);
		guidance.m_decoy = res;
		guidance.m_fuelLeft = fuel;
		guidance.m_activateAfter = activateAfter;
		guidance.m_activeReflectorProto = activeReflectorProto;
		return res;
	}
}


final class PassiveDecoyFactory: WeaponFactory
{
	PropulsorFactory propFactory;	/// passive decoys have predefined propulsors
	usecs_t activateAfter = 4_000_000;

	/// Verify launch params, build torpedo entity and assign launch params to guidance
	override StaticDecoy build(Submarine shooter,
		const(WeaponParamValue)[] launchParams, Tube tube) const
	{
		enforce(launchParams.length == 0, "decoy is not configurable");
		PassiveDecoyGuidance guidance = new PassiveDecoyGuidance();
		StaticDecoy res = new StaticDecoy(shooter, name, tube, guidance);
		res.addPropulsor(propFactory.build());
		super.bootstrap(res);
		guidance.m_decoy = res;
		guidance.m_fuelLeft = fuel;
		guidance.m_activateAfter = activateAfter;
		return res;
	}
}


final class TorpedoFactory: WeaponFactory
{
	PropulsorFactory propFactory;	/// torpedoes have predefined propulsors
	MountPoint propMount;
	HydrophonePrototype* hprot;
	ActiveSonarPrototype* asprot;
	MountPoint sensorsMount;
	ReflectorPrototype* activeReflectorProto;
	// snake
	float snakeArm = 300.0f;
	float snakeArmInitial;
	float snakeAngle = dgr2rad(45.0f);
	// spiral
	float spiralStartTarget = 1.0f;
	float spiralTargetRedPerRange = 1e-2f;
	// guidance
	float trackAngVelKi = 1.0f;
	int pingIntervalSearch = 7;
	PrerecordedSoundPrototype detonationSoundProto;
	// detection margins
	int sonarNoiseMargin = 15;
	int hydrophoneNoiseMargin = ushort.max / 12;
	// detonator
	float detonationMassK = 4.5f;
	float blastRadius = 70.0f;

	this(PropulsorFactory pf)
	{
		propFactory = pf;
		marchCourseConfigurable = true;
	}

	// balancing params
	float tgtMaxRangeOnMaxSpd;
	float balancingStddev = 0.01f;

	/// Prepare balance-costrained factory parameters and template param descriptions and values.
	void prepareDynamicsAndParams()
	{
		generateParamDescs();
		// tune drag to match expected performace
		rigidBody.Cd1.mean =
			(propFactory.posThrustK.mean - rigidBody.Cd0.mean * fullThrottleSpd) / pow(fullThrottleSpd, 2);
		assert(rigidBody.Cd1.mean >= 0, "negative Cd1");
		rigidBody.Cd1.stddev = rigidBody.Cd1.mean * balancingStddev;
		// tune Cl to match turning radius
		rigidBody.Cl.mean = calcClForTurningRadius(
			steering.equilDrift, turningRadius, rigidBody.mass.mean);
		assert(rigidBody.Cl.mean >= 0, "negative Cl");
		rigidBody.Cl.stddev = rigidBody.Cl.mean * balancingStddev;
		// tune fuel to match expected range
		fuel.mean = tgtMaxRangeOnMaxSpd / fullThrottleSpd;
		fuel.stddev = fuel.mean * balancingStddev;
		float minThrottle = throttleForSpeed(
			rigidBody.Cd0.mean, rigidBody.Cd1.mean, 1, propFactory.posThrustK.mean,
			marchSpeedRange.min);
		trace("Max range of ", propFactory.name, " on min speed ", marchSpeedRange.min,
			": ", marchSpeedRange.min * (fuel.mean / pow(minThrottle, fuelEffExponent)));
		trace("Max range of ", propFactory.name, " on max speed ", activeSpeedRange.max,
			": ", activeSpeedRange.max * (fuel.mean / pow(1.0f, fuelEffExponent)));
	}

	// used by AI
	float maxRangeAtSpeed(float speed)
	{
		float throttle = throttleForSpeed(
			rigidBody.Cd0.mean, rigidBody.Cd1.mean, 1, propFactory.posThrustK.mean,
			speed);
		// lowball estimate by using activeSpeedRange.min
		return activeSpeedRange.min * (fuel.mean / pow(throttle, fuelEffExponent));
	}

	private void bootstrap(Torpedo res) const
	{
		super.bootstrap(res);
		assert(res.rigidBody.mass > 0.0f);
		res.propulsors[0].transform.position = propMount.mountCenter.tod;
		res.propulsors[0].transform.rotation = propMount.rotation;
		if (activeReflectorProto)
			res.guidance.m_activeReflectorProto = activeReflectorProto;
		res.guidance.m_detonationMassK = detonationMassK;
		res.guidance.m_blastRadius = blastRadius;
		res.guidance.m_fuelLeft = fuel;
		res.guidance.m_fuelEffExponent = fuelEffExponent;
		res.guidance.m_snakeArm = snakeArm;
		res.guidance.m_snakeArmBeforeTurn = snakeArmInitial;
		res.guidance.m_snakeAngle = snakeAngle;
		res.guidance.m_spiralStartTarget = spiralStartTarget;
		res.guidance.m_spiralTargetRedPerRange = spiralTargetRedPerRange;
		res.guidance.m_trackAngVelKi = trackAngVelKi;
		res.guidance.m_pingIntervalSearch = pingIntervalSearch;
		res.guidance.m_detonationSoundProto = cast() detonationSoundProto;
		res.guidance.m_sonarNoiseMargin = sonarNoiseMargin;
		res.guidance.m_hydrophoneNoiseMargin = hydrophoneNoiseMargin;
		if (hprot)
		{
			Transform2D t = new Transform2D();
			t.position = sensorsMount.mountCenter.tod;
			t.rotation = sensorsMount.rotation;
			res.transform.addChild(t);
			Hydrophone h = new Hydrophone(Globals.sctx.queue(0), t, *hprot);
			res.m_hydrophone = h;
			h.onPreKinematics += { h.ktsStart = res.rigidBody.kinet.progradeSpeed.mps2kts; };
			h.onPostKinematics += { h.ktsEnd = res.rigidBody.kinet.progradeSpeed.mps2kts; };
			h.shouldBeActive = false;
			h.muteTds = true;
		}
		if (asprot)
		{
			Transform2D t = new Transform2D();
			t.position = sensorsMount.mountCenter.tod;
			t.rotation = sensorsMount.rotation;
			res.transform.addChild(t);
			res.m_sonar = new ActiveSonar(Globals.sctx.queue(0), t, *asprot);
			res.m_sonar.owner = res;
			res.m_sonar.onPreKinematics += ()
			{
				res.m_sonar.angVelStart = res.rigidBody.kinet.angVel;
				res.m_sonar.ktsStart = res.rigidBody.kinet.progradeSpeed.mps2kts;
			};
			res.m_sonar.onPostKinematics += ()
			{
				res.m_sonar.angVelEnd = res.rigidBody.kinet.angVel;
				res.m_sonar.ktsEnd = res.rigidBody.kinet.progradeSpeed.mps2kts;
			};
		}
		// guidance final configuration
		assert(!isNaN(res.guidance.m_marchSpeed));
		res.guidance.m_marchThrottle = throttleForSpeed(res, res.guidance.m_marchSpeed);
		assert(isNormal(res.guidance.m_marchThrottle));
		assert(!isNaN(res.guidance.m_activeSpeed));
		res.guidance.m_activeThrottle = throttleForSpeed(res, res.guidance.m_activeSpeed);
		assert(isNormal(res.guidance.m_activeThrottle));
	}

	/// Assign guidance parameters, specified by the client. Validate untrusted data.
	void configureGuidance(Torpedo torp, const(WeaponParamValue)[] params) const
	{
		TorpedoGuidance g = torp.guidance;
		// first we assign default values
		g.m_sensorMode = defaultSensorMode;
		g.m_searchPattern = defaultSearchPattern;
		g.m_marchSpeed = marchSpeedRange.max;
		g.m_activeSpeed = activeSpeedRange.max;
		g.m_activationRange = activationRange.min;
		g.m_minActivationRange = activationRange.min;
		// then we process client input
		WeaponParamType assignedParams;
		foreach (const WeaponParamValue param; params)
		{
			enforce(popcnt(param.type) == 1, "must choose one parameter to set");
			enforce(param.type & m_availableParams, "parameter " ~
				param.type.to!string ~ " is unavailable");
			enforce((param.type & assignedParams) == 0, "parameter " ~
				param.type.to!string ~ " is already assigned");
			switch (param.type)
			{
				case WeaponParamType.course:
					g.m_marchCourse = param.course.validateFloat.clampAngle;
					break;
				case WeaponParamType.sensorMode:
					enforce(sensorModes & param.sensorMode, "invalid sensor mode");
					enforce(popcnt(param.sensorMode) <= 1, "must choose at most one");
					g.m_sensorMode = param.sensorMode;
					break;
				case WeaponParamType.searchPattern:
					enforce(searchPatterns.availablePatterns & param.searchPattern,
						"invalid search pattern");
					enforce(popcnt(param.searchPattern) == 1, "must choose one");
					g.m_searchPattern = param.searchPattern;
					break;
				case WeaponParamType.marchSpeed:
					enforce(marchSpeedRange.contains(param.speed), "invalid marchSpeed");
					g.m_marchSpeed = param.speed;
					break;
				case WeaponParamType.activeSpeed:
					enforce(activeSpeedRange.contains(param.speed), "invalid activeSpeed");
					g.m_activeSpeed = param.speed;
					break;
				case WeaponParamType.activationRange:
					enforce(activationRange.contains(param.range), "invalid activationRange");
					g.m_activationRange = param.range;
					break;
				default:
					throw new Exception("unknown weapon parameter");
			}
			assignedParams |= param.type;
		}
	}

	/// Verify launch params, build torpedo entity and assign launch params to guidance
	override Torpedo build(Submarine shooter, const(WeaponParamValue)[] launchParams,
		Tube tube) const
	{
		Torpedo res = new Torpedo(shooter, name, tube);
		res.addPropulsor(propFactory.build());
		configureGuidance(res, launchParams);
		bootstrap(res);
		return res;
	}
}