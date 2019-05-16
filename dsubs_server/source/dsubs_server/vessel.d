module dsubs_server.vessel;

import dsubs_common.api.entities;
import dsubs_common.math;
import dsubs_common.containers.array: removeFirstUnstable;

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
		@property void propulsor(Propulsor rhs)
		{
			assert(m_propulsor is null, "only can assign propulsor once");
			m_propulsor = rhs;
			m_transform.addChild(rhs.transform);
		}
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

	/// register the vessel in global component systems
	void register()
	{
		m_rigidBody.updateFromTransform();
		Globals.vessels.registerEntity(this);
		Globals.phys.registerEntity(m_rigidBody);
		Globals.acous.registerReflector(m_reflector);
		m_propulsor.register();
	}

	/// call this when removing this submarine from the physical world to
	/// unregister components and dispose of resources
	void shutdown()
	{
		Globals.vessels.unregisterEntity(this);
		Globals.acous.unregisterReflector(m_reflector);
		Globals.phys.unregisterEntity(m_rigidBody);
		m_propulsor.shutdown();
	}
}


/// Set of vessels that are active
final class VesselCollection
{
	private
	{
		Vessel[] m_entities;
	}

	void registerEntity(Vessel e)
	{
		synchronized(this)
		{
			m_entities ~= e;
		}
	}

	void unregisterEntity(Vessel e)
	{
		synchronized(this)
		{
			m_entities.removeFirstUnstable(e);
		}
	}

	/// shutdown all elements of the collection and clear the container
	void clean()
	{
		Vessel[] entities = m_entities;
		foreach(e; entities)
			e.shutdown();
		assert(m_entities.length == 0, "vessel leak");
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

	/// All internal binding and preparation of vessel components
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
		// rudder and propulsor
		assert(res.m_rudder !is null);
		assert(res.m_propulsor !is null);
		res.m_rigidBody.forces = [cast(IForce) res.m_rudder, cast(IForce) res.m_propulsor];
		// add module masses to the hull
		res.m_rigidBody.mass += res.m_propulsor.mass;
		// calculate final MOI
		res.m_rigidBody.moi = res.calcMoi();
		res.m_propulsor.bootstrap(res.m_rigidBody);
		assert(!isNaN(res.m_rigidBody.mass));
		assert(!isNaN(res.m_rigidBody.moi));
	}
}