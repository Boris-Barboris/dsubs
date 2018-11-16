#define dB float
#define Intensity float
#define IntensityLevel dB


float toDb(const float linear)
{
	return 10.0f * log10(linear);
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

// http://www.bealto.com/gpu-fft_fft.html

// Return A*B
float2 cmul(float2 a, float2 b)
{
	return (float2)(
		a.x * b.x - a.y * b.y,
		a.x * b.y + a.y * b.x);
}

// Return A * exp(K*ALPHA*i)
float2 twiddle(float2 a, int k, float alpha)
{
	float cs, sn;
	sn = sincos((float)k * alpha, &cs);
	return cmul(a, (float2)(cs, sn));
}

// In-place DFT-2, output is (a,b). Arguments must be variables.
#define DFT2(a,b) { float2 tmp = a - b; a += b; b = tmp; }

// Compute T x DFT-2.
// T is the number of threads.
// N = 2*T is the size of input vectors.
// X[N], Y[N]
// P is the length of input sub-sequences: 1,2,4,...,T.
// Each DFT-2 has input (X[I],X[I+T]), I=0..T-1,
// and output Y[J],Y|J+P], J = I with one 0 bit inserted at postion P. */
void __kernel fftRadix2Kernel(__global const float2 *x, __global float2 *y, int p)
{
	int t = get_global_size(0);		// thread count
	int i = get_global_id(0);		// thread index
	int k = i & (p - 1);			// index in input sequence, in 0..P-1
	int j = ((i - k) << 1) + k;		// output index
	float alpha = -M_PI * (float)k / (float)p;

	// Read and twiddle input
	x += i;
	float2 u0 = x[0];
	float2 u1 = twiddle(x[t], 1, alpha);

	// In-place DFT-2
	DFT2(u0, u1);

	// Write output
	y += j;
	y[0] = u0;
	y[p] = u1;
}

void __kernel ifftRadix2Kernel(__global const float2 *x, __global float2 *y, int p, int last)
{
	int t = get_global_size(0);		// thread count
	int i = get_global_id(0);		// thread index
	int k = i & (p - 1);			// index in input sequence, in 0..P-1
	int j = ((i - k) << 1) + k;		// output index
	float alpha = M_PI * (float)k / (float)p;

	// Read and twiddle input
	x += i;
	float2 u0 = x[0];
	float2 u1 = twiddle(x[t], 1, alpha);

	// In-place DFT-2
	DFT2(u0, u1);

	// Write output
	y += j;
	if (last == 0)
	{
		y[0] = u0;
		y[p] = u1;
	}
	else
	{
		y[0] = u0 / (2.0f * t);
		y[p] = u1 / (2.0f * t);
	}
}


// radix-4 functions

// twiddle_P_Q(A) returns A * EXP(-P*PI*i/Q)
float2 twiddle_1_2(float2 a)
{
	// A * (-i)
	return (float2)(a.y, -a.x);
}

float2 itwiddle_1_2(float2 a) { return (float2)(a.y, a.x); }

// In-place DFT-4, output is (a,c,b,d). Arguments must be variables.
#define DFT4(a,b,c,d) { DFT2(a,c); DFT2(b,d); d=twiddle_1_2(d); DFT2(a,b); DFT2(c,d); }
#define iDFT4(a,b,c,d) { DFT2(a,c); DFT2(b,d); d=itwiddle_1_2(d); DFT2(a,b); DFT2(c,d); }

// Compute T x DFT-4.
// T is the number of threads.
// N = 4*T is the size of input vectors.
// X[N], Y[N]
// P is the length of input sub-sequences: 1,4,16,...,T.
// Each DFT-4 has input (X[I],X[I+T],X[I+2*T],X[I+3*T]), I=0..T-1,
// and output (Y[J],Y|J+P],Y[J+2*P],Y[J+3*P], J = I with two 0 bits inserted at postion P. */
void __kernel fftRadix4Kernel(__global const float2 *x, __global float2 *y, int p)
{
	int t = get_global_size(0); // thread count
	int i = get_global_id(0); // thread index
	int k = i & (p - 1); // index in input sequence, in 0..P-1
	int j = ((i - k) << 2) + k; // output index
	float alpha = -M_PI * (float)k / (float)(2 * p);

	// Read and twiddle input
	x += i;
	float2 u0 = x[0];
	float2 u1 = twiddle(x[t], 1, alpha);
	float2 u2 = twiddle(x[2 * t], 2, alpha);
	float2 u3 = twiddle(x[3 * t], 3, alpha);

	// In-place DFT-4
	DFT4(u0, u1, u2, u3);

	// Shuffle and write output
	y += j;
	y[0] = u0;
	y[p] = u2;
	y[2 * p] = u1;
	y[3 * p] = u3;
}

void __kernel ifftRadix4Kernel(__global const float2 *x, __global float2 *y, int p, int last)
{
	int t = get_global_size(0); // thread count
	int i = get_global_id(0); // thread index
	int k = i & (p - 1); // index in input sequence, in 0..P-1
	int j = ((i - k) << 2) + k; // output index
	float alpha = M_PI * (float)k / (float)(2 * p);

	// Read and twiddle input
	x += i;
	float2 u0 = x[0];
	float2 u1 = twiddle(x[t], 1, alpha);
	float2 u2 = twiddle(x[2 * t], 2, alpha);
	float2 u3 = twiddle(x[3 * t], 3, alpha);

	// In-place DFT-4
	DFT4(u0, u1, u2, u3);

	// Shuffle and write output
	y += j;
	if (last == 0)
	{
		y[0] = u0;
		y[p] = u2;
		y[2 * p] = u1;
		y[3 * p] = u3;
	}
	else
	{
		y[0] = u0 / (4.0f * t);
		y[p] = u2 / (4.0f * t);
		y[2 * p] = u1 / (4.0f * t);
		y[3 * p] = u3 / (4.0f * t);
	}
}