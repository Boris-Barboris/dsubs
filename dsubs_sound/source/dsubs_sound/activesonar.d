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


struct Chirp
{
	int startFreq;
	int endFreq;
	float duration;
}

struct PingParameters
{
	/// radial (range) resolution, meters
	float radRes = 50.0f;
	/// number of radial slices. Determines max range.
	int radCount = 10000 / 50;
	float lifeTime = 3.0f;
	Chirp[] chirps;
	float effectiveFreq;	/// abstracted away "main" frequency
	dB pingLevel;
	/// reference reflection intensity that corrensponds to full white color in the image
	dB refMaxLevel = 140.0f;
}


final class SonarPing: SoundSource
{
	this(vec2d position, PingParameters params)
	{
		m_position = position;
		m_params = params;
	}

	private
	{
		// time passed since ping creation
		float m_timeSince = 0.0f;
		vec2d m_position;
		PingParameters m_params;
		TimeDomainSignal m_tds;
		ubyte[][] m_image;
	}

	override @property vec2d position() { return m_position; }

	/// build tds and stuff
	private void precalculate()
	{

	}
}