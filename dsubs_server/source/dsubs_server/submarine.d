module dsubs_server.submarine;

import dsubs_common.api.entities;
import dsubs_common.math;

import dsubs_sound.activesonar;
import dsubs_sound.hydrophone;

import dsubs_server.common;
import dsubs_server.vessel;
import dsubs_server.player: Player;
import dsubs_server.propulsion;


/// Server-side model of a submarine
final class Submarine: Vessel
{
	private
	{
		Hydrophone[] m_hydrophones;
		ActiveSonar m_sonar;
		Player m_owner;
		int m_spawnId;
	}

	@property int spawnId() const { return m_spawnId; }
	@property inout(Hydrophone)[] hydrophones() inout { return m_hydrophones; }
	@property ActiveSonar sonar() { return m_sonar; }

	/// creates transform and rigid body
	this(Player owner, string prototypeName)
	{
		assert(owner);
		super(prototypeName);
		m_owner = owner;
		m_spawnId = uniform(0, int.max);
	}

	override void bootstrap()
	{
		super.bootstrap();
		foreach (h; m_hydrophones)
		{
			h.onPreSimulation += () { h.ktsStart = m_rigidBody.kinet.progradeSpeed.mps2kts; };
			h.onPostSimulation += () { h.ktsEnd = m_rigidBody.kinet.progradeSpeed.mps2kts; };
			Globals.acous.registerHydrophone(h);
		}
		// active sonar stuff
		m_sonar.onPreSimulation += ()
			{
				m_sonar.angVelStart = m_rigidBody.kinet.angVel;
				m_sonar.ktsStart = m_rigidBody.kinet.progradeSpeed.mps2kts;
			};
		m_sonar.onPostSimulation += ()
			{
				m_sonar.angVelEnd = m_rigidBody.kinet.angVel;
				m_sonar.ktsEnd = m_rigidBody.kinet.progradeSpeed.mps2kts;
			};
		Globals.acous.registerSonar(m_sonar);
	}

	override void shutdown()
	{
		super.shutdown();
		foreach (h; m_hydrophones)
			Globals.acous.unregisterHydrophone(h);
		Globals.acous.unregisterSonar(m_sonar);
		if (m_owner)
		{
			m_owner.unsetSubmarine(this);
			m_owner = null;
		}
	}

	@property float targetThrottle() const { return m_propulsor.targetThrottle; }

	/// set propulsor's target throttle
	@property void targetThrottle(float target)
	{
		enforce(!isNaN(target), "NaN target throttle");
		enforce(target <= 1.0f && target >= -1.0f, "Throttle not in [-1, 1] interval");
		m_propulsor.targetThrottle = target;
	}

	@property float targetCourse() const { return m_rudder.targetCourse; }

	/// set rudder's target course
	@property void targetCourse(float target)
	{
		enforce(!isNaN(target), "NaN target course");
		enforce(!isInfinity(target), "Infinite target course");
		m_rudder.targetCourse = clampAngle(target);
	}
}


final class SubmarineFactory: VesselFactory
{
	immutable SubmarineTemplate tmpl;
	HydrophonePrototype[] hprots;
	ActiveSonarPrototype asprot;

	this(immutable SubmarineTemplate t)
	{
		super(t.name);
		tmpl = t;
	}

	protected void bootstrap(Submarine res) const
	{
		super.bootstrap(res);
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

	Submarine build(Player p) const
	{
		Submarine res = new Submarine(p, tmpl.name);
		bootstrap(res);
		return res;
	}
}