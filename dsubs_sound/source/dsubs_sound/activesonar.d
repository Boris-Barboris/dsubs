module dsubs_sound.activesonar;

import std.algorithm;

import dsubs_common.event;

import dsubs_sound.common;
import dsubs_sound.spectrum;
import dsubs_sound.soundsource;
import dsubs_sound.water;



/// Rectangular reflector of active sonar impulses
final class Reflector
{
	this(Transform2D t)
	{
		m_transform = t;
	}

	private Transform2D m_transform;

	final @property Transform2D transform() { return m_transform; }

	// rectangle size...
	private vec2f m_size;
	// and area
	private float m_area;

	@property vec2f size() const { return m_size; }

	@property void size(vec2f rhs)
	{
		m_size = rhs;
		m_area = m_size.x * m_size.y;
	}

	@property float area() const { return m_area; }

	private vec2f m_reflectivity;
}


struct ActiveSonarPrototype
{
	int dirRes = 90;			/// directional resolution
	float radRes = 100.0f;		/// radial resolution
	float
}

/// Module that pings and receives echoes
final class ActiveSonar: SoundSource
{

}