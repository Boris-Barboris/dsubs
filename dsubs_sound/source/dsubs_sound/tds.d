module dsubs_sound.tds;

import dsubs_sound.common;
import dsubs_sound.opencl;


/// OpenCL-backed time-domain signal of one second length
final class TdsSecond: Buffer
{
	this(DsubsSoundOpenclCtx ctx)
	{
		super(ctx, GLOBAL_SRATE * float.sizeof);
	}

	AsyncEvent startRead(ref float[GLOBAL_SRATE] dest,
		const (AsyncEvent)* onlyAfter = null)
	{
		return enqueueFullRead(&dest[0], onlyAfter);
	}

	void fullRead(ref float[GLOBAL_SRATE] dest, const (AsyncEvent)* onlyAfter = null)
	{
		super.fullRead(&dest[0], onlyAfter);
	}
}