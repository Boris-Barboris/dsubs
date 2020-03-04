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
}


abstract class Weapon: Vessel
{
	protected
	{
		Submarine m_shooter;
		Captain m_shooterCaptain;
		IGuidance m_guidance;
	}

	final @property Submarine shooter() { return m_shooter; }
	final @property Captain shooterCaptain() { return m_shooterCaptain; }
	@property IGuidance guidance() { return m_guidance; }

	// all detonated weapons will be unregistered by weapons
	// component during updateGuidances().
	@property bool detonated() const;

	this(Submarine shooter, string templateName)
	{
		super(templateName);
		m_shooter = shooter;
		if (m_shooter)
			m_shooterCaptain = shooter.captain;
	}

	override void register(Simulator sim)
	{
		super.register(sim);
		m_guidance.setUnassignedParams();
		simulator.weapons.registerEntity(this);
	}

	override void shutdown()
	{
		super.shutdown();
		m_guidance.shutdown();
		simulator.weapons.unregisterEntity(this);
	}
}


final class StaticDecoy: Weapon
{
	this(Submarine shooter, string templateName, IGuidance guidance)
	{
		super(shooter, templateName);
		m_guidance = guidance;
	}

	override @property bool detonated() const { return false; }
}


final class ActiveDecoyGuidance: IGuidance
{
	private
	{
		StaticDecoy m_decoy;
		bool m_active;
		usecs_t m_activateAfter;
		float m_fuelLeft;
		ReflectorPrototype m_activeReflectorProto;
		Reflector m_activeReflector;
	}

	void update(usecs_t dt)
	{
		if (!m_active)
		{
			m_activateAfter -= dt;
			if (m_activateAfter <= 0)
			{
				m_active = true;
				m_activeReflector = new Reflector(m_decoy.transform,
					m_activeReflectorProto);
				m_decoy.simulator.acous.registerReflector(m_activeReflector);
			}
		}
		else
		{
			m_fuelLeft -= dt / 1e6;
			if (m_fuelLeft < 0.0f)
			{
				m_decoy.kill("fuel exhausted");
				if (m_activeReflector)
				{
					m_decoy.simulator.acous.unregisterReflector(m_activeReflector);
					m_activeReflector = null;
				}
			}
		}
	}

	void shutdown()
	{
		if (m_activeReflector)
			m_decoy.simulator.acous.unregisterReflector(m_activeReflector);
	}

	void setUnassignedParams() {}
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

	this(Submarine shooter, string templateName)
	{
		super(shooter, templateName);
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

	override bool kill(string cause)
	{
		bool res = super.kill(cause);
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


/// Torpedo guidance, detonation and fuel controller
final class TorpedoGuidance: IGuidance
{
	private
	{
		Torpedo m_torpedo;
		WeaponSensorMode m_sensorMode;
		WeaponSearchPattern m_searchPattern;
		float m_marchCourse;
		float m_activeCourse;
		float m_marchSpeed;
		float m_activeSpeed;
		float m_marchThrottle = 1.0f;
		float m_activeThrottle = 1.0f;
		float m_fuelLeft;
		float m_fuelEffExponent = 2.0f;
		float m_distanceTraveled = 0.0f;
		float m_activeRange;
		vec2d m_lastPos;
		bool m_activated;

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
		m_pingTdsOffset = uniform(0, GLOBAL_SRATE);
	}

	void shutdown() {}

	/// verify some variables that could have been missed for some reason
	void setUnassignedParams()
	{
		// dumbfire snapshot in straight direction
		if (isNaN(m_marchCourse))
			m_marchCourse = m_torpedo.transform.wrotation;
		if (isNaN(m_activeCourse))
			m_activeCourse = m_marchCourse;
	}

	void update(usecs_t dt)
	{
		// perform fuel-related calculations
		float fuelSpent = pow(m_torpedo.propulsor.throttle.fabs, m_fuelEffExponent);
		m_fuelLeft -= fuelSpent;
		if (m_fuelLeft < 0.0f)
		{
			m_torpedo.kill("fuel exhausted");
			return;
		}
		// activation logic
		float distanceAdded = (m_lastPos - m_torpedo.transform.wposition).length;
		m_distanceTraveled += distanceAdded;
		m_lastPos = m_torpedo.transform.wposition;
		if (!m_activated && m_distanceTraveled >= m_activeRange)
		{
			m_activated = true;
			m_snakeArmBeforeTurn += m_snakeArm;
		}
		// assign course and throttle based on activation state
		if (m_activated)
		{
			// first we check if we should detonate.
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
						m_torpedo.targetCourse = m_activeCourse;
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
						m_torpedo.targetCourse = m_activeCourse +
							m_snakeSign * m_snakeAngle;
						break;
				}
			}
			else
			{
				// homing mode
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

	private
	{
		usecs_t m_sinceLastPing;
		size_t m_pingTdsOffset;
		int m_pingIntervalSearch;
		SonarPing m_currentPing;
		ubyte[] m_sonarImage;
		size_t m_sliceByteSize;
		bool m_detonatorFired;
		double m_closestDetonatorDist = double.max;
	}

	// detonation logic tries to detonate as late as possible
	private bool detonateIfNeeded(RigidBody[] closeBodies)
	{
		bool inDetonationRange;
		double currentClosestDetonatorDist = double.max;
		foreach (RigidBody rb; closeBodies)
		{
			double triggerDist = pow(rb.mass, 1.0f / 3) * m_detonationMassK;
			double dist = (m_torpedo.transform.wposition - rb.transform.wposition).length;
			if (triggerDist >= dist)
			{
				inDetonationRange = true;
				currentClosestDetonatorDist = min(currentClosestDetonatorDist, dist);
			}
		}

		void chooseKilledAndDetonate()
		{
			Killable[] inKillRadius;
			foreach (RigidBody rb; closeBodies)
			{
				double dist = (m_torpedo.transform.wposition - rb.transform.wposition).length;
				if (rb.owner && dist <= m_blastRadius)
					inKillRadius ~= rb.owner;
			}
			detonate(inKillRadius);
		}

		// we're tracking detonator now
		if (m_detonatorFired)
		{
			if (!inDetonationRange || currentClosestDetonatorDist > m_closestDetonatorDist)
			{
				// we're losing magnetic contact
				chooseKilledAndDetonate();
				return true;
			}
		}
		if (inDetonationRange)
		{
			m_detonatorFired = true;
			m_closestDetonatorDist = min(m_closestDetonatorDist, currentClosestDetonatorDist);
		}
		return false;
	}

	private void detonate(Killable[] inKillRadius)
	{
		trace("Torpedo detonated!!!");
		m_torpedo.m_detonated = true;
		foreach (v; inKillRadius)
		{
			bool isActuallyKilled = v.kill(
				"Killed by " ~ m_torpedo.prototypeName ~ " torpedo");
			if (isActuallyKilled)
			{
				trace(v, " is killed in explosion");
				if (Globals.database && m_torpedo.simulator.id == "main_arena")
				{
					void reportFunc()
					{
						try
						{
							Globals.database.insertKillRecord(
								m_torpedo.shooterCaptain,
								m_torpedo.shooter,
								v, m_torpedo);
						}
						catch (Exception ex)
						{
							error("error during kill report: ", ex.toString);
						}
					}
					Globals.auxTaskPool.put(task(&reportFunc));
				}
			}
			else
				trace(v, " is in explosion radius");
		}
		m_torpedo.kill("detonation");
		SoundSource detonationSoundSource = new PrerecordedSoundSource(
			new Transform2D(m_torpedo.transform.wposition),
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
	bool activeCourseConfigurable;
	bool playable;

	@property const(WeaponTemplate) tmpl() const
	{
		assert(m_paramDescsGenerated);
		return const WeaponTemplate(
			name, description, turningRadius, m_availableParams, m_paramDescs,
			fuel.mean, fullThrottleSpd, fuelEffExponent);
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
			m_availableParams |= WeaponParamType.marchCourse;
		if (activeCourseConfigurable)
			m_availableParams |= WeaponParamType.activeCourse;
		if (marchSpeedRange.max > marchSpeedRange.min)
		{
			m_availableParams |= WeaponParamType.marchSpeed;
			WeaponParamDesc pd;
			pd.type = WeaponParamType.marchSpeed;
			pd.speedRange = marchSpeedRange;
			m_paramDescs ~= pd;
		}
		if (activeSpeedRange.max > activeSpeedRange.min)
		{
			m_availableParams |= WeaponParamType.activeSpeed;
			WeaponParamDesc pd;
			pd.type = WeaponParamType.activeSpeed;
			pd.speedRange = activeSpeedRange;
			m_paramDescs ~= pd;
		}
		if (activationRange.max > activationRange.min)
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
		m_paramDescsGenerated = true;
	}

	Weapon build(Submarine shooter, const(WeaponParamValue)[] launchParams) const;
}


final class ActiveDecoyFactory: WeaponFactory
{
	ReflectorPrototype activeReflectorProto =
		ReflectorPrototype(vec2f(30, 30), [-7.0f, -7.0f, -7.0f]);
	usecs_t activateAfter = 4_000_000;

	/// Verify launch params, build torpedo entity and assign launch params to guidance
	override StaticDecoy build(Submarine shooter,
		const(WeaponParamValue)[] launchParams) const
	{
		enforce(launchParams.length == 0, "decoy is not configurable");
		ActiveDecoyGuidance guidance = new ActiveDecoyGuidance();
		StaticDecoy res = new StaticDecoy(shooter, name, guidance);
		super.bootstrap(res);
		guidance.m_decoy = res;
		guidance.m_fuelLeft = fuel;
		guidance.m_activateAfter = activateAfter;
		guidance.m_activeReflectorProto = activeReflectorProto;
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
	// snake
	float snakeArm = 300.0f;
	float snakeArmInitial;
	float snakeAngle = dgr2rad(45.0f);
	// spiral
	float spiralStartTarget = 1.0f;
	float spiralTargetRedPerRange = 1e-2f;
	// guidance
	float trackAngVelKi = 1.0f;
	int pingIntervalSearch = 10;
	PrerecordedSoundPrototype detonationSoundProto;
	// detection margins
	int sonarNoiseMargin = 15;
	int hydrophoneNoiseMargin = ushort.max / 12;

	this(PropulsorFactory pf)
	{
		propFactory = pf;
		marchCourseConfigurable = true;
		activeCourseConfigurable = true;
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
		rigidBody.Cd1.stddev = rigidBody.Cd1.mean * balancingStddev;
		// tune Cl to match turning radius
		rigidBody.Cl.mean = calcClForTurningRadius(steering.equilDrift, turningRadius, rigidBody.mass.mean);
		rigidBody.Cl.stddev = rigidBody.Cl.mean * balancingStddev;
		// tune fuel to match expected range
		fuel.mean = tgtMaxRangeOnMaxSpd / fullThrottleSpd;
		fuel.stddev = fuel.mean * balancingStddev;
	}

	private void bootstrap(Torpedo res) const
	{
		super.bootstrap(res);
		assert(res.rigidBody.mass > 0.0f);
		res.propulsor.transform.position = propMount.mountCenter.tod;
		res.propulsor.transform.rotation = propMount.rotation;
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
		g.m_activeRange = activationRange.min;
		// then we process client input
		WeaponParamType assignedParams;
		foreach (const WeaponParamValue param; params)
		{
			enforce(popcnt(param.type) == 1, "must choose one parameter to set");
			enforce(param.type & m_availableParams, "parameter " ~
				param.type.to!string ~ " is unavailable");
			enforce((param.type & assignedParams) == 0, "parameter " ~
				param.type.to!string ~ " is already assigned");
			enforce(param.type != WeaponParamType.none, "invalid parameter type");
			switch (param.type)
			{
				case WeaponParamType.marchCourse:
					g.m_marchCourse = param.course.validateFloat.clampAngle;
					break;
				case WeaponParamType.activeCourse:
					g.m_activeCourse = param.course.validateFloat.clampAngle;
					break;
				case WeaponParamType.sensorMode:
					enforce(sensorModes & param.sensorMode, "invalid sensor mode");
					enforce(popcnt(param.sensorMode) == 1, "must choose one");
					enforce(param.sensorMode != WeaponSensorMode.activePassive,
						"alternating mode not implemented");
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
					enforce(activationRange.contains(param.range), "invalid activeRange");
					g.m_activeRange = param.range;
					break;
				default:
					throw new Exception("unknown weapon parameter");
			}
			assignedParams |= param.type;
		}
	}

	/// Verify launch params, build torpedo entity and assign launch params to guidance
	override Torpedo build(Submarine shooter, const(WeaponParamValue)[] launchParams) const
	{
		Torpedo res = new Torpedo(shooter, name);
		res.propulsor = propFactory.build();
		configureGuidance(res, launchParams);
		bootstrap(res);
		return res;
	}
}