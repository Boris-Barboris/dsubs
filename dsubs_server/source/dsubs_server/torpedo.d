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
	}

	override void register()
	{
		super.register();
		if (m_hydrophone)
			Globals.acous.registerHydrophone(m_hydrophone);
		if (m_sonar)
			Globals.acous.registerSonar(m_sonar);
	}

	override void shutdown()
	{
		super.shutdown();
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
		float m_marchSpeed;
		float m_fuelLeft;
	}

	this(Torpedo owner)
	{
		m_torpedo = owner;
	}

	private void update(float dt)
	{

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
		res.m_guidance = new TorpedoGuidance(res);
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