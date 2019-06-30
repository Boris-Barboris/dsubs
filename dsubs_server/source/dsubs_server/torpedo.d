module dsubs_server.torpedo;

import core.bitop: popcnt;

import dsubs_common.api.constants;
import dsubs_common.api.entities;
import dsubs_common.math;
import dsubs_common.event;

import dsubs_sound.activesonar;
import dsubs_sound.hydrophone;
import dsubs_sound.common: uniform, GLOBAL_SRATE;

import dsubs_server.common;
import dsubs_server.vessel;
import dsubs_server.propulsion;
import dsubs_server.submarine: Submarine;


/// Server-side torpedo model
final class Torpedo: Vessel
{
	private
	{
		Hydrophone m_hydrophone;
		ActiveSonar m_sonar;
		Submarine m_shooter;
		TorpedoGuidance m_guidance;
		const TorpedoFactory m_factory;
	}

	@property Submarine shooter() { return m_shooter; }
	@property inout(Hydrophone) hydrophone() inout { return m_hydrophone; }
	@property ActiveSonar sonar() { return m_sonar; }
	@property TorpedoGuidance guidance() { return m_guidance; }
	@property const(TorpedoFactory) factory() const { return m_factory; }

	this(Submarine shooter, const TorpedoFactory fact)
	{
		super(fact.templateName);
		m_factory = fact;
		m_shooter = shooter;
		m_guidance = new TorpedoGuidance(this);
	}

	override void register()
	{
		super.register();
		Globals.torps.registerEntity(this);
		targetThrottle = 1.0f;	// by-default torps spawn with max throttle
		m_guidance.m_lastPos = transform.position;
		m_guidance.setUnassignedParams();
		if (m_hydrophone)
		{
			m_hydrophone.active = true;
			Globals.acous.registerHydrophone(m_hydrophone);
		}
		if (m_sonar)
		{
			m_sonar.active = true;
			Globals.acous.registerSonar(m_sonar);
		}
	}

	override void shutdown()
	{
		super.shutdown();
		Globals.torps.unregisterEntity(this);
		if (m_hydrophone)
		{
			Globals.acous.unregisterHydrophone(m_hydrophone);
			m_hydrophone.release();
		}
		if (m_sonar)
		{
			Globals.acous.unregisterSonar(m_sonar);
			m_sonar.release();
		}
	}
}


/// Torpedo guidance, detonation and fuel controller
final class TorpedoGuidance
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
		bool m_exhausted;

		// snake-related parameters
		float m_snakeArm;
		float m_snakeAngle = dgr2rad(45);
		float m_snakeArmBeforeTurn;
		float m_snakeSign = 1.0f;

		// spiral-related parameters
		float m_spiralStartTarget = 1.0f;
		float m_spiralTargetRedPerRange;
		float m_spiralSinceStart = 0.0f;
	}

	@property void fuelLeft(float rhs) { m_fuelLeft = rhs; }

	@property Torpedo torpedo() { return m_torpedo; }

	private this(Torpedo owner)
	{
		m_torpedo = owner;
		m_pingTdsOffset = uniform(0, GLOBAL_SRATE);
	}

	/// verify some variables that could have been missed for some reason
	void setUnassignedParams()
	{
		// dumbfire snapshot in straight direction
		if (isNaN(m_marchCourse))
			m_marchCourse = m_torpedo.rigidBody.kinet.rotation;
		if (isNaN(m_activeCourse))
			m_activeCourse = m_torpedo.rigidBody.kinet.rotation;
	}

	void update(usecs_t dt)
	{
		// perform fuel-related calculations
		if (m_exhausted)
			return;
		float fuelSpent = pow(m_torpedo.propulsor.throttle.fabs, m_fuelEffExponent);
		m_fuelLeft -= fuelSpent;
		if (m_fuelLeft < 0.0f)
		{
			m_torpedo.targetThrottle = 0.0f;
			m_exhausted = true;
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
			if (!handleSensors(dt))
			{
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
		int m_pingIntervalSearch = 5;
		SonarPing m_currentPing;
		ubyte[] m_sonarImage;
		size_t m_sliceByteSize;
	}

	Event!(void delegate(ubyte[] image, int w, int h)) onSonarImageReady;

	/// process sensor signals and, if homing, return true.
	private bool handleSensors(usecs_t dt)
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
						onSonarImageReady(m_sonarImage,
							sonar.proto.getSliceXResol(),
							sonar.proto.radialRes * (sliceId + 1));
					}
				}
				if (m_sinceLastPing == 0)
				{
					m_currentPing = sonar.startPing(
						sonar.proto.maxPeakIlevel, &m_pingTdsOffset);
					assert(m_currentPing);
					Globals.acous.registerPing(m_currentPing);
					m_sliceByteSize =
						sonar.proto.getSliceXResol() * sonar.proto.radialRes;
					m_sonarImage.length = m_sliceByteSize * sonar.maxSec;
				}
				m_sinceLastPing += dt;
				if (m_sinceLastPing >= m_pingIntervalSearch * 1_000_000)
					m_sinceLastPing = 0;
				break;
			}
			default:
				assert(0, "not implemented");
		}
		return false;
	}

	/// look for targets in the sonar slice
	private void processSonarSlice(const(ubyte)[] slice, int sliceId)
	{
		ActiveSonar sonar = m_torpedo.m_sonar;
	}
}


final class TorpedoCollection
{
	private
	{
		Torpedo[] m_torpedoes;
	}

	void registerEntity(Torpedo e)
	{
		synchronized(this)
		{
			m_torpedoes ~= e;
		}
	}

	void unregisterEntity(Torpedo e)
	{
		synchronized(this)
		{
			m_torpedoes.removeFirstUnstable(e);
		}
	}

	void clean()
	{
		m_torpedoes.length = 0;
	}

	void updateGuidances(usecs_t dt)
	{
		foreach (Torpedo torp; Globals.taskPool.parallel(m_torpedoes, 4))
			torp.guidance.update(dt);
	}
}


final class TorpedoFactory: VesselFactory
{
	immutable WeaponTemplate tmpl;
	PropulsorFactory propFactory;	/// torpedoes have predefined propulsors
	MountPoint propMount;
	HydrophonePrototype* hprot;
	ActiveSonarPrototype* asprot;
	MountPoint sensorsMount;
	RolledF fuel;
	float fuelEffExponent = 2.0f;
	// snake
	float snakeArm = 300.0f;
	float snakeArmInitial;
	float snakeAngle = dgr2rad(45.0f);
	// spiral
	float spiralStartTarget = 1.0f;
	float spiralTargetRedPerRange = 1e-2f;
	// inlined weapon parameter descriptions
	MinMax marchSpeedRange;
	MinMax activeSpeedRange;
	MinMax activationRange;
	WeaponSensorMode sensorModes;
	WeaponSensorMode defaultSensorMode;
	WeaponSearchPattern defaultSearchPattern = WeaponSearchPattern.straight;
	WeaponParamDescSearchPatterns searchPatterns;

	this(immutable WeaponTemplate t, PropulsorFactory pf)
	{
		super(t.name);
		tmpl = t;
		propFactory = pf;
		assignParamDescsFromTemplate();
	}

	/// Take some torpedo parameters from the WeaponTemplate and assign them
	/// to relevant factory fields. TODO: reverse the logic. Server-side source of
	/// truth should be a factory object, and the template should be generated from it.
	private void assignParamDescsFromTemplate()
	{
		foreach (const(WeaponParamDesc) desc; tmpl.paramDescs)
		{
			switch (desc.type)
			{
				case WeaponParamType.sensorMode:
					sensorModes = desc.sensorModes;
					break;
				case WeaponParamType.marchSpeed:
					marchSpeedRange = desc.speedRange;
					break;
				case WeaponParamType.activeSpeed:
					activeSpeedRange = desc.speedRange;
					break;
				case WeaponParamType.searchPattern:
					searchPatterns = desc.searchPatterns;
					break;
				case WeaponParamType.activationRange:
					activationRange = desc.activationRange;
					break;
				default:
					assert(0, "unexpected parameter type");
			}
		}
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
		if (hprot)
		{
			Transform2D t = new Transform2D();
			t.position = sensorsMount.mountCenter.tod;
			t.rotation = sensorsMount.rotation;
			res.transform.addChild(t);
			Hydrophone h = new Hydrophone(Globals.sctx.queue(0), t, *hprot);
			res.m_hydrophone = h;
			h.onPreSimulation += { h.ktsStart = res.rigidBody.kinet.progradeSpeed.mps2kts; };
			h.onPostSimulation += { h.ktsEnd = res.rigidBody.kinet.progradeSpeed.mps2kts; };
		}
		if (asprot)
		{
			Transform2D t = new Transform2D();
			t.position = sensorsMount.mountCenter.tod;
			t.rotation = sensorsMount.rotation;
			res.transform.addChild(t);
			res.m_sonar = new ActiveSonar(Globals.sctx.queue(0), t, *asprot);
			res.m_sonar.onPreSimulation += ()
			{
				res.m_sonar.angVelStart = res.rigidBody.kinet.angVel;
				res.m_sonar.ktsStart = res.rigidBody.kinet.progradeSpeed.mps2kts;
			};
			res.m_sonar.onPostSimulation += ()
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
			enforce(param.type & tmpl.availableParams, "parameter " ~
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
					enforce(param.sensorMode == WeaponSensorMode.active, "only active sensor mode implemented");
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
	Torpedo build(Submarine shooter, const(WeaponParamValue)[] launchParams) const
	{
		Torpedo res = new Torpedo(shooter, this);
		res.propulsor = propFactory.build();
		configureGuidance(res, launchParams);
		bootstrap(res);
		return res;
	}
}