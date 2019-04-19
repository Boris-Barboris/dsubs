module dsubs_server.torpedo;

import dsubs_common.api.entities;
import dsubs_common.math;

import dsubs_sound.activesonar;
import dsubs_sound.hydrophone;

import dsubs_server.common;
import dsubs_server.dynamics;
import dsubs_server.player: Player;
import dsubs_server.propulsion;


/// Server-side torpedo model
final class Torpedo
{
	private
	{
		Transform2D m_transform;
		RigidBody m_rigidBody;
		float m_moiK = 1.0f;
		float m_hullLength;
		// universally-present modules
		Rudder m_rudder;
		Propulsor m_propulsor;
		Reflector m_reflector;
		// name of the torpedo prototype
		string m_prototypeName;

		// optional modules
		Hydrophone m_hydrophone;
		ActiveSonar m_sonar;
		const string m_shooter;
	}

	final @property Transform2D transform() { return m_transform; }
	@property RigidBody rigidBody() { return m_rigidBody; }
	@property inout(Propulsor) propulsor() inout { return m_propulsor; }
	@property inout(Rudder) rudder() inout { return m_rudder; }
	@property string prototypeName() const { return m_prototypeName; }
	@property Hydrophone hydrophone() { return m_hydrophone; }
	@property ActiveSonar sonar() { return m_sonar; }

	this(const string shooter, string prototypeName)
	{
		m_shooter = shooter;
		m_prototypeName = prototypeName;
	}

	private double calcMoi() const
	{
		return m_moiK * m_rigidBody.mass * m_hullLength * m_hullLength / 12.0;
	}
}