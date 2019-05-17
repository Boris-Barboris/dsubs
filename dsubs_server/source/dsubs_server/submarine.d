module dsubs_server.submarine;

import dsubs_common.api.entities;
import dsubs_common.math;

import dsubs_sound.activesonar;
import dsubs_sound.hydrophone;

import dsubs_server.common;
import dsubs_server.vessel;
import dsubs_server.propulsion: Propulsor;
import dsubs_server.player: Player;


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
		super(prototypeName);
		m_owner = owner;
		m_spawnId = uniform(0, int.max);
	}

	override void register()
	{
		super.register();
		foreach (h; m_hydrophones)
			Globals.acous.registerHydrophone(h);
		Globals.acous.registerSonar(m_sonar);
	}

	override void shutdown()
	{
		super.shutdown();
		foreach (h; m_hydrophones)
		{
			Globals.acous.unregisterHydrophone(h);
			h.release();
		}
		Globals.acous.unregisterSonar(m_sonar);
		m_sonar.release();
		if (m_owner)
		{
			m_owner.unsetSubmarine(this);
			m_owner = null;
		}
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

	private void bootstrap(Submarine res) const
	{
		super.bootstrap(res);
		// propulsor shift according to first mount
		assert(tmpl.propulsionMounts.length == 1);
		res.propulsor.transform.position = tmpl.propulsionMounts[0].mountCenter.tod;
		res.propulsor.transform.rotation = tmpl.propulsionMounts[0].rotation;
		// hydrophones
		foreach (i, ref hp; hprots)
		{
			Transform2D t = new Transform2D();
			t.position = tmpl.hydrophones[i].mount.mountCenter.tod;
			t.rotation = tmpl.hydrophones[i].mount.rotation;
			res.transform.addChild(t);
			Hydrophone h = new Hydrophone(Globals.sctx.queue(0), t, hp);
			res.m_hydrophones ~= h;
			h.onPreSimulation += { h.ktsStart = res.rigidBody.kinet.progradeSpeed.mps2kts; };
			h.onPostSimulation += { h.ktsEnd = res.rigidBody.kinet.progradeSpeed.mps2kts; };
		}
		// active sonar
		{
			Transform2D t = new Transform2D();
			t.position = tmpl.sonar.mount.mountCenter.tod;
			t.rotation = tmpl.sonar.mount.rotation;
			res.transform.addChild(t);
			res.m_sonar = new ActiveSonar(Globals.sctx.queue(0), t, asprot);
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

	Submarine build(Player p, Propulsor prop) const
	{
		Submarine res = new Submarine(p, tmpl.name);
		res.propulsor = prop;
		bootstrap(res);
		return res;
	}
}