module dsubs_server.vessel;

import dsubs_common.api.entities;
import dsubs_common.math;

import dsubs_sound.activesonar: Reflector, ReflectorPrototype;

import dsubs_server.common;
import dsubs_server.dynamics;
import dsubs_server.propulsion;


/// Physically-simulated vessel with propulsor, rudder and reflector components
class Vessel
{
	protected
	{
		Transform2D m_transform;
		RigidBody m_rigidBody;
		float m_moiK = 1.0f;
		float m_hullLength;
		Rudder m_rudder;
		Propulsor m_propulsor;
		Reflector m_reflector;
		string m_prototypeName;
	}

	final
	{
		@property Transform2D transform() { return m_transform; }
		@property RigidBody rigidBody() { return m_rigidBody; }
		/// Propulsor is assigned before bootstrap, during spawn
		@property void propulsor(Propulsor rhs) { m_propulsor = rhs; }
		@property inout(Propulsor) propulsor() inout { return m_propulsor; }
		@property inout(Rudder) rudder() inout { return m_rudder; }
		@property string prototypeName() const { return m_prototypeName; }
	}

	this(string prototypeName)
	{
		m_prototypeName = prototypeName;
		m_transform = new Transform2D();
		m_rigidBody = new RigidBody(m_transform);
	}

	private double calcMoi() const
	{
		return m_moiK * m_rigidBody.mass * m_hullLength * m_hullLength / 12.0;
	}

	/// call this once after assigning all modules and initial values,
	/// to entangle all internal connections and register the vessel in global systems
	void bootstrap()
	{
		assert(m_rudder !is null);
		assert(m_propulsor !is null);
		m_rigidBody.forces = [cast(IForce) m_rudder, cast(IForce) m_propulsor];
		m_transform.addChild(m_propulsor.transform);
		// add module masses to the hull
		m_rigidBody.mass += m_propulsor.mass;
		m_propulsor.bootstrap(m_rigidBody);
		// calculate final MOI
		m_rigidBody.moi = calcMoi();
		assert(!isNaN(m_rigidBody.mass));
		assert(!isNaN(m_rigidBody.moi));
		// register entities
		Globals.phys.registerEntity(m_rigidBody);
		Globals.acous.registerReflector(m_reflector);
	}

	/// call this when removing this submarine from the physical world
	void shutdown()
	{
		Globals.acous.unregisterReflector(m_reflector);
		Globals.phys.unregisterEntity(m_rigidBody);
		m_propulsor.shutdown();
	}
}


class VesselFactory
{
	const string templateName;
	// physical characteristics
	RolledF mass, Cd0, Cd1, Cr0, Cr1, Cl, Cm;
	double Cda;
	// MOI-related stuff
	float moiK = 1.0f;
	float hullLength;
	/// Equilibrium drift angle on maximum rudder deflection, radians
	float equilDrift;
	ReflectorPrototype reflprot;

	this(string templateName)
	{
		this.templateName = templateName;
	}

	protected final void bootstrap(Vessel res) const
	{
		res.m_moiK = moiK;
		res.m_hullLength = hullLength;
		res.m_rigidBody.mass = mass;
		res.m_rigidBody.hydroModel.Cd0 = Cd0;
		res.m_rigidBody.hydroModel.Cd1 = Cd1;
		res.m_rigidBody.hydroModel.Cda = Cda;
		res.m_rigidBody.hydroModel.Cr0 = Cr0;
		res.m_rigidBody.hydroModel.Cr1 = Cr1;
		res.m_rigidBody.hydroModel.Cl = Cl;
		res.m_rigidBody.hydroModel.Cm = -Cm.roll();
		// res.m_rigidBody.kinet.angVel = 1.0;
		auto brudder = new BasicRudder();
		brudder.transform = res.transform;
		// Cm * equilDrift = steeringK
		brudder.steeringK = fabs(equilDrift * res.m_rigidBody.hydroModel.Cm);
		res.m_rudder = brudder;
		// reflector
		res.m_reflector = new Reflector(res.transform, reflprot);
	}

	final Vessel build() const
	{
		Vessel res = new Vessel(templateName);
		bootstrap(res);
		return res;
	}
}