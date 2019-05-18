module dsubs_server.torpedo;

import core.bitop: popcnt;

import dsubs_common.api.constants;
import dsubs_common.api.entities;
import dsubs_common.math;

import dsubs_sound.activesonar;
import dsubs_sound.hydrophone;

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
		targetThrottle = 1.0f;	// by-default torps spawn with max throttle
	}

	override void register()
	{
		super.register();
		Globals.torps.registerEntity(this);
		m_guidance.m_lastPos = transform.position;
		if (m_hydrophone)
			Globals.acous.registerHydrophone(m_hydrophone);
		if (m_sonar)
			Globals.acous.registerSonar(m_sonar);
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
		float m_marchThrottle;
		float m_activeThrottle;
		float m_fuelLeft;
		float m_distanceTraveled = 0.0f;
		float m_activeRange;
		vec2d m_lastPos;
		bool m_activated;
		bool m_exhausted;
	}

	@property Torpedo torpedo() { return m_torpedo; }

	private this(Torpedo owner)
	{
		m_torpedo = owner;
	}

	void update(float dt)
	{
		// perform fuel-related calculations
		if (m_exhausted)
			return;
		m_fuelLeft -= m_torpedo.propulsor.throttle;
		if (m_fuelLeft < 0.0f)
		{
			m_torpedo.propulsor.targetThrottle = 0.0f;
			m_exhausted = true;
			return;
		}
		// activation logic
		m_distanceTraveled += (m_lastPos - m_torpedo.transform.position).length;
		if (!m_activated && m_distanceTraveled >= m_activeRange)
			m_activated = true;
		// assign course and throttle based on activation state
		if (m_activated)
		{
			m_torpedo.targetThrottle = m_activeThrottle;
			m_torpedo.targetCourse = m_activeCourse;
		}
		else
		{
			m_torpedo.targetThrottle = m_marchThrottle;
			m_torpedo.targetCourse = m_marchCourse;
		}
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

	void updateGuidances(float dt)
	{
		foreach (i, ref torp; Globals.taskPool.parallel(m_torpedoes, 8))
			torp.guidance.update(dt);
	}
}


final class TorpedoFactory: VesselFactory
{
	immutable WeaponTemplate tmpl;
	PropulsorFactory propFactory;	/// torpedoes have predefined propulsors
	MountPoint propMount;
	HydrophonePrototype* hprot;
	MountPoint hmount;
	ActiveSonarPrototype* asprot;
	MountPoint asmount;
	RolledF fuel;
	// inlined weapon parameter descriptions
	MinMax marchSpeedRange;
	MinMax activeSpeedRange;
	MinMax activationRange;
	WeaponSensorMode sensorModes;
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
				case(WeaponParamType.sensorMode):
					sensorModes = desc.sensorModes;
					break;
				case(WeaponParamType.marchSpeed):
					marchSpeedRange = desc.speedRange;
					break;
				case(WeaponParamType.activeSpeed):
					marchSpeedRange = desc.speedRange;
					break;
				case(WeaponParamType.searchPattern):
					searchPatterns = desc.searchPatterns;
					break;
				case(WeaponParamType.activationRange):
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
		res.propulsor.transform.position = propMount.mountCenter.tod;
		res.propulsor.transform.rotation = propMount.rotation;
		res.guidance.m_fuelLeft = fuel;
		if (hprot)
		{
			Transform2D t = new Transform2D();
			t.position = hmount.mountCenter.tod;
			t.rotation = hmount.rotation;
			res.transform.addChild(t);
			Hydrophone h = new Hydrophone(Globals.sctx.queue(0), t, *hprot);
			res.m_hydrophone = h;
			h.onPreSimulation += { h.ktsStart = res.rigidBody.kinet.progradeSpeed.mps2kts; };
			h.onPostSimulation += { h.ktsEnd = res.rigidBody.kinet.progradeSpeed.mps2kts; };
		}
		if (asprot)
		{
			Transform2D t = new Transform2D();
			t.position = asmount.mountCenter.tod;
			t.rotation = asmount.rotation;
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
		res.guidance.m_marchThrottle = throttleForSpeed(res, res.guidance.m_marchSpeed);
		res.guidance.m_activeThrottle = throttleForSpeed(res, res.guidance.m_activeSpeed);
	}

	/// Assign guidance parameters, specified by the client. Validate untrusted data.
	void configureGuidance(Torpedo torp, const(WeaponParamValue)[] params) const
	{
		WeaponParamType assignedParams;
		TorpedoGuidance g = torp.guidance;
		foreach (const WeaponParamValue param; params)
		{
			enforce(param.type & tmpl.availableParams, "this parameter is unavailable");
			enforce(param.type & assignedParams, "this parameter is already assigned");
			enforce(param.type != WeaponParamType.none, "invalid parameter type");
			switch (param.type)
			{
				case(WeaponParamType.marchCourse):
					g.m_marchCourse = param.course.validateFloat.clampAngle;
					break;
				case(WeaponParamType.activeCourse):
					g.m_activeCourse = param.course.validateFloat.clampAngle;
					break;
				case(WeaponParamType.sensorMode):
					enforce(sensorModes & param.sensorMode, "invalid sensor mode");
					enforce(popcnt(param.sensorMode) == 1, "must choose one");
					g.m_sensorMode = param.sensorMode;
					break;
				case(WeaponParamType.searchPattern):
					enforce(searchPatterns.availablePatterns & param.searchPattern,
						"invalid search pattern");
					enforce(popcnt(param.searchPattern) == 1, "must choose one");
					g.m_searchPattern = param.searchPattern;
					break;
				case(WeaponParamType.marchSpeed):
					enforce(marchSpeedRange.contains(param.speed), "invalid marchSpeed");
					g.m_marchSpeed = param.speed;
					break;
				case(WeaponParamType.activeSpeed):
					enforce(activeSpeedRange.contains(param.speed), "invalid activeSpeed");
					g.m_activeSpeed = param.speed;
					break;
				case(WeaponParamType.activationRange):
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