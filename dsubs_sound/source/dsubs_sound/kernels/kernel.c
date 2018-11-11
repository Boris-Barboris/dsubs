#define dB float
#define Intensity float
#define IntensityLevel dB


float toDb(const float linear)
{
	return 10.0f * log10f(linear);
}

float toLinear(const dB db)
{
	return powr(10.0f, db / 10.0f);
}

/// construct initial rng seed from ixternal seed constant and globIdx
ulong getInitState(ulong seed, int globIdx)
{
	return seed + globIdx;
}

ulong xorshift64(ulong *state)
{
	ulong x = *state;
	x^= x << 13;
	x^= x >> 7;
	x^= x << 17;
	*state = x;
	return x;
}

float uniform01(ulong *state)
{
	ulong seed = xorshift64(state);
	return (float) seed / ULONG_MAX;
}

float uniform(ulong *state, float lower, float upper)
{
	return uniform01(state) * (upper - lower) + lower;
}

// KERNEL
// Filter TDS with FIR filter. Maps curSource to dest, with respect to past
// history of signal, contained in prevSource.
void __kernel firTds(
	__global const float *curSource,
	__global const float *prevSource,
	__constant float *taps,
	const int tapCount,
	__global float *dest)
{
	const int tdsSize = get_global_size(0);
	const int idx = get_global_id(0);
	float outVal = 0.0;
	int i = 0;

	for (i = 0; i < tapCount; i++)
	{
		const int curIdx = idx - i;
		float sourceVal;
		if (curIdx >= 0)
			sourceVal = curSource[curIdx];
		else
			sourceVal = prevSource[tdsSize + curIdx];
		outVal += sourceVal * taps[i];
	}
	dest[idx] = outVal;
}