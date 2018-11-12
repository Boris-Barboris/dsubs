module dsubs_sound.tds;

import dsubs_sound.common;
import dsubs_sound.opencl;


/// OpenCL-backed time-domain signal sample of fixed length
final class Tds(int len): Buffer
{
	this(DsubsSoundOpenclCtx ctx)
	{
		super(ctx, len * float.sizeof);
	}

	AsyncEvent startRead(CommandQueue q, ref float[len] dest,
		const (AsyncEvent)* onlyAfter = null)
	{
		return enqueueFullRead(q, &dest[0], onlyAfter);
	}

	void fullRead(CommandQueue q, ref float[len] dest, const (AsyncEvent)* onlyAfter = null)
	{
		super.fullRead(q, &dest[0], onlyAfter);
	}
}

alias TdsSecond = Tds!GLOBAL_SRATE;