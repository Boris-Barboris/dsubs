module dsubs_sound.hydrophone;

import dsubs_common.math;

import dsubs_sound.common;
import dsubs_sound.spectrum;
import dsubs_sound.soundsource;
import dsubs_sound.modulation;


struct HydrophonePrototype
{
	AntennaePrototype[] antennaes;
	int minFreq, maxFreq;
	dB directivity = 0.0f;
	dB baseNoise = 1.0f;
}

struct AntennaePrototype
{
	int elementCount;
	float rot;
	float span;
}

final class Hydrophone
{
	this(Transform2D t, HydrophonePrototype p)
	{
		assert(p.minFreq >= 20 && p.maxFreq >= p.minFreq);
		m_transform = t;
		foreach (ap; p.antenaaes)
			m_ant ~= Antennae(ap.elementCount, ap.rot, ap.span);
		m_minFreq = p.minFreq;
		m_maxFreq = p.maxFreq;
		m_directivity = p.directivity;
		m_baseNoise = p.baseNoise;
	}

	private
	{
		Transform2D m_transform;
		Antennae[] m_ant;
		int m_minFreq, m_maxFreq;
		dB m_directivity = 0.0f;
		dB m_baseNoise = 0.0f;
	}

	/// Continuous block of hydrophone elements
	private final class Antennae
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
			Intensity[] elements;
			float rot;	// rotation relative to hydrophone transform
			float span;
			float cellAngle;
		}

		/// reset elements array to zero energies
		void reset()
		{
			foreach (ref i; elements)
				i = Intensity(0.0f);
		}

		bool sourceVisible(SoundSource s, vec2d wTargetDir) const
		{
			vec2d relTargetDir = rotateVector(wTargetDir,
				-outer.m_transform.wrotation - rot);
			double relBearing = courseAngle(relTargetDir);
			return (relBearing <= span / 2 + MAX_HALO_2) ||
				(relBearing >= -span / 2 - MAX_HALO_2);
		}

		/// max size of sound halo
		static immutable double MAX_HALO = dgr2rad(15);
		static immutable double MAX_HALO_2 = MAX_HALO / 2;
	}
}