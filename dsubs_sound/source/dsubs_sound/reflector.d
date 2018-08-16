module dsubs_sound.reflector;

import std.algorithm;

import dsubs_common.event;

import dsubs_sound.common;
import dsubs_sound.spectrum;
import dsubs_sound.water;




/// Thing that reflects active sonar impulses
abstract class Reflector
{
	this(Transform2D t)
	{
		m_transform = t;
	}

	private Transform2D m_transform;

	final @property Transform2D transform() { return m_transform; }

	void buildReflection(vec2d listenerPos, int freq, float dissMod = 1.0f) const;
}