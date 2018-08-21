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

	// reflectivities of front, sides and rear
	private vec3f m_reflect;
}

struct ActiveSonarPrototype
{
	float radRes = 50.0f;		/// radial resolution, meters
	int freqBandStart;
	int freqBandEnd;
}

final class SonarPing: SoundSource
{
	float timeSince = 0.0f;
}