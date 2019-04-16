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
	}
}