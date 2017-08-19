module dsubs_client.math.transform;

import derelict.sfml2.graphics;
import derelict.sfml2.system;

public import dsubs_common.math.transform;
import dsubs_client.lib.sfml;

class Transform: Transform2D
{
	protected sfTransform _sfmat;   // sfml-specific matrix

	@property ref const(sfTransform) sfglobal()
	{
		if (dirty)
			rebuild();
		return _sfmat;
	}

	override void rebuild()
	{
		super.rebuild();
		_sfmat = world_cache.tosf;
	}
}
