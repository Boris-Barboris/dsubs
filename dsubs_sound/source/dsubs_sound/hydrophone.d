module dsubs_sound.hydrophone;

import dsubs_common.math;

import dsubs_sound.common;
import dsubs_sound.spectrum;
import dsubs_sound.modulation;


/// Continuous block of hydrophone elements
struct Antennae
{
	this(int elementCount, float mainAxisRot, float span)
	{
		assert(elementCount > 0);
		assert(span > 0.0f && span <= 2 * PI);
		rot = mainAxisRot;
		this.span = span;
		cellAngle = span / elementCount;
		elements.length = elementCount;
	}

	private
	{
		// intensities are additive, intensity levels are not
		Intensity[] elements;
		float rot;	// rotation relative to hydrophone transform
		float span;
		float cellAngle;
	}

	bool dirBelongsTo(float relBearing) const
	{
		return (relBearing <= rot + span / 2) ||
			(relBearing >= rot - span / 2);
	}
}

struct AntennaePrototype
{
	int elementCount;
	float rot;
	float span;
}

final class Hydrophone
{
	this(Transform2D t, int minFreq, int maxFreq, AntennaePrototype[] antenaaes)
	{
		assert(minFreq >= 20 && maxFreq >= minFreq);
		m_transform = t;
		foreach (ap; antenaaes)
			m_ant ~= Antennae(ap.elementCount, ap.rot, ap.span);
		m_minFreq = minFreq;
		m_maxFreq = maxFreq;
	}

	private
	{
		Transform2D m_transform;
		Antennae[] m_ant;
		int m_minFreq, m_maxFreq;
	}
	dB directivity = 0.0f;
}