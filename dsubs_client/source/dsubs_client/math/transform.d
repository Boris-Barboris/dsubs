module dsubs_client.math.transform;

import derelict.sfml2.graphics;
import derelict.sfml2.system;

import dsubs_client.lib.sfml: tosf;
public import dsubs_common.math;


/** Wrapper that converts double-precision dsubs transform to
single-precision sfml matrix. */
final class Transform: Transform2D
{
	private sfTransform m_sfmat;

	@property ref const(sfTransform) sfWorld()
	{
		if (m_dirty)
			rebuild();
		return m_sfmat;
	}

	protected override void rebuild()
	{
		super.rebuild();
		m_sfmat = world.tosf;
	}
}
