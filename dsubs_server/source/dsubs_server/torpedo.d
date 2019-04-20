module dsubs_server.torpedo;

import dsubs_common.api.constants;
import dsubs_common.api.entities;
import dsubs_common.math;

import dsubs_sound.activesonar;
import dsubs_sound.hydrophone;

import dsubs_server.common;
import dsubs_server.vessel;
import dsubs_server.player: Player;


/// Server-side torpedo model
final class Torpedo: Vessel
{
	private
	{
		Hydrophone m_hydrophone;
		ActiveSonar m_sonar;
		Player m_shooter;
		TorpedoGuidance m_guidance;
	}

	@property Player shooter() const { return m_shooter; }
	@property inout(Hydrophone) hydrophone() inout { return m_hydrophone; }
	@property ActiveSonar sonar() { return m_sonar; }
	@property TorpedoGuidance guidance() { return m_guidance; }

	this(Player shooter, string prototypeName)
	{
		super(prototypeName);
		m_shooter = shooter;
	}
}

final class TorpedoFactory: VesselFactory
{
	immutable WeaponTemplate tmpl;
	PropulsorFactory propFactory;	/// torpedoes have fixed propulsors
	HydrophonePrototype hprot;
	ActiveSonarPrototype asprot;
	RolledF fuel;

	this(immutable WeaponTemplate t, PropulsorFactory pf)
	{
		super(t.name);
		tmpl = t;
		propFactory = pf;
	}

	private void bootstrap(Torpedo res) const
	{
		super.bootstrap(res);
		// propulsor is fixed
		res.propulsor = propFactory.build();
		res.m_guidance = new TorpedoGuidance(res);
		// hydrophones
		foreach (i, ref hp; hprots)
		{
			Transform2D t = new Transform2D();
			t.position = tmpl.hydrophones[i].mount.mountCenter.tod;
			t.rotation = tmpl.hydrophones[i].mount.rotation;
			res.transform.addChild(t);
			res.m_hydrophones ~= new Hydrophone(Globals.sctx.queue(0), t, hp);
		}
		// active sonar
		{
			Transform2D t = new Transform2D();
			t.position = tmpl.sonar.mount.mountCenter.tod;
			t.rotation = tmpl.sonar.mount.rotation;
			res.transform.addChild(t);
			res.m_sonar = new ActiveSonar(Globals.sctx.queue(0), t, asprot);
		}
	}

	/// Verify launch params, build torpedo entity and assign launch params to guidance
	Torpedo build(Player p, WeaponParamValue[] launchParams) const
	{
		Torpedo res = new Torpedo(p, tmpl.name);
		bootstrap(res);
		return res;
	}
}

/// Torpedo guidance, detonator and sinking controller
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