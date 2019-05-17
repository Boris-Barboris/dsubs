module dsubs_server.torpedo;

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
	}

	@property Submarine shooter() { return m_shooter; }
	@property inout(Hydrophone) hydrophone() inout { return m_hydrophone; }
	@property ActiveSonar sonar() { return m_sonar; }
	@property TorpedoGuidance guidance() { return m_guidance; }

	this(Submarine shooter, string prototypeName)
	{
		super(prototypeName);
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
	public
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

	/// perform physics update for all entities
	void updateGuidances(float dt)
	{
		foreach (i, ref torp; Globals.taskPool.parallel(m_torpedoes, 8))
			torp.guidance.update(dt);
	}
}


final class TorpedoFactory: VesselFactory
{
	immutable WeaponTemplate tmpl;
	PropulsorFactory propFactory;	/// torpedoes have fixed propulsors
	MountPoint propMount;
	HydrophonePrototype* hprot;
	MountPoint hmount;
	ActiveSonarPrototype* asprot;
	MountPoint asmount;
	RolledF fuel;

	this(immutable WeaponTemplate t, PropulsorFactory pf)
	{
		super(t.name);
		tmpl = t;
		propFactory = pf;
	}

	private void bootstrap(Torpedo res) const
	{
		// propulsor is fixed per torpedo design
		res.propulsor = propFactory.build();
		res.propulsor.transform.position = propMount.mountCenter.tod;
		res.propulsor.transform.rotation = propMount.rotation;
		super.bootstrap(res);
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
	}

	/// Verify launch params, build torpedo entity and assign launch params to guidance
	Torpedo build(Submarine shooter, WeaponParamValue[] launchParams) const
	{
		Torpedo res = new Torpedo(shooter, tmpl.name);
		bootstrap(res);
		return res;
	}
}