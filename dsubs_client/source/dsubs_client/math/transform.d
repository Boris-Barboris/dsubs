module dsubs_client.math.transform;

import derelict.sfml2.graphics;
import derelict.sfml2.system;

import dsubs_client.lib.sfml: tosf;
public import dsubs_common.math.transform;

/** Wrapper that converts double-precision dsubs transform to
single-precision sfml matrix. */
class Transform: Transform2D
{
	protected sfTransform m_sfmat;

	final @property ref const(sfTransform) sfWorld()
	{
		if (m_dirty)
			rebuild();
		return m_sfmat;
	}

	protected override void rebuild()
	{
		super.rebuild();
		m_sfmat = m_worldCache.tosf;
	}
}
