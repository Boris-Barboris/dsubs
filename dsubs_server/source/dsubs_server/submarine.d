module dsubs_server.submarine;

import dsubs_common.api.entities;
import dsubs_common.math;

import dsubs_sound.hydrophone;

import dsubs_server.common;
import dsubs_server.dynamics;
import dsubs_server.player: Player;
import dsubs_server.propulsion;


/// Server-side model of a submarine
final class Submarine
{
	private
	{
		Transform2D m_transform;
		RigidBody m_rigidBody;
		float m_moiK = 1.0f;
		float m_hullLength;	// will be replaced

		// modules of various nature
		Rudder m_rudder;
		Propulsor m_propulsor;
		Hydrophone[] m_hydrophones;

		// player reference
		Player m_owner;

		/// name of the submarine type
		string m_prototypeName;

		int m_spawnId;
	}

	final @property Transform2D transform() { return m_transform; }

	@property RigidBody rigidBody() { return m_rigidBody; }

	@property void propulsor(Propulsor rhs)
	{
		m_propulsor = rhs;
	}

	@property inout(Propulsor) propulsor() inout { return m_propulsor; }

	@property inout(Rudder) rudder() inout { return m_rudder; }

	@property string prototypeName() const { return m_prototypeName; }

	@property int spawnId() const { return m_spawnId; }

	@property Hydrophone[] hydrophones() { return m_hydrophones; }
	@property const(Hydrophone)[] hydrophones() const { return m_hydrophones; }

	/// creates transform and rigid body
	this(Player owner, string prototypeName)
	{
		assert(owner);
		m_transform = new Transform2D();
		m_owner = owner;
		m_prototypeName = prototypeName;
		m_rigidBody = new RigidBody(m_transform);
		m_spawnId = uniform(0, int.max);
	}

	private double calcMoi() const
	{
		return m_moiK * m_rigidBody.mass * m_hullLength * m_hullLength / 12.0;
	}

	/// call this once after assigning all modules and initial values,
	/// to entangle all internal connections and register the submarine
	void bootstrap()
	{
		assert(m_rudder !is null);
		assert(m_propulsor !is null);

		m_rigidBody.forces = [cast(IForce) m_rudder, cast(IForce) m_propulsor];
		m_transform.addChild(m_propulsor.transform);
		foreach (h; m_hydrophones)
		{
			h.onPreSimulation += () { h.ktsStart = m_rigidBody.kinet.progradeSpeed.mps2kts;	};
			h.onPostSimulation += () { h.ktsEnd = m_rigidBody.kinet.progradeSpeed.mps2kts; };
			Globals.acous.registerHydrophone(h);
		}
		// add module masses to the hull
		m_rigidBody.mass += m_propulsor.mass;
		m_propulsor.bootstrap(m_rigidBody);
		// calculate final MOI
		m_rigidBody.moi = calcMoi();
		assert(!isNaN(m_rigidBody.mass));
		assert(!isNaN(m_rigidBody.moi));
		trace("hull length ", m_hullLength);
		trace("sub ", m_prototypeName, ", mass ", m_rigidBody.mass, ", moi ", m_rigidBody.moi);
		// register entities
		Globals.phys.registerEntity(m_rigidBody);
	}

	/// call this when removing this submarine from the physical world
	void shutdown()
	{
		Globals.phys.unregisterEntity(m_rigidBody);
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


final class SubmarineFactory
{
	immutable SubmarineTemplate tmpl;
	// physical characteristics
	RolledF mass, Cd0, Cd1, Cr, Cl, Cm;

	// MOI-related stuff
	float moiK = 1.0f;
	float hullLength;

	/// Equilibrium drift angle on maximum rudder deflection, radians
	float equilDrift;

	// hydrophpone prototypes
	HydrophonePrototype[] hprots;

	this(immutable SubmarineTemplate t)
	{
		tmpl = t;
	}

	Submarine build(Player p) const
	{
		Submarine res = new Submarine(p, tmpl.name);
		res.m_moiK = moiK;
		res.m_hullLength = hullLength;
		res.m_rigidBody.mass = mass;
		res.m_rigidBody.hydroModel.Cd0 = Cd0;
		res.m_rigidBody.hydroModel.Cd1 = Cd1;
		res.m_rigidBody.hydroModel.Cr = Cr;
		res.m_rigidBody.hydroModel.Cl = Cl;
		res.m_rigidBody.hydroModel.Cm = -Cm.roll();
		auto brudder = new BasicRudder();
		brudder.transform = res.transform;
		// Cm * equilDrift = steeringK
		brudder.steeringK = fabs(equilDrift * res.m_rigidBody.hydroModel.Cm);
		res.m_rudder = brudder;
		// hydrophones
		foreach (i, ref hp; hprots)
		{
			Transform2D t = new Transform2D();
			t.position = tmpl.hydrophones[i].mount.mountCenter.toGfm!double;
			t.rotation = tmpl.hydrophones[i].mount.rotation;
			res.transform.addChild(t);
			res.m_hydrophones ~= new Hydrophone(t, hp);
		}
		return res;
	}

	immutable(SubmarineTemplate)* getTemplate() const
	{
		return &tmpl;
	}
}