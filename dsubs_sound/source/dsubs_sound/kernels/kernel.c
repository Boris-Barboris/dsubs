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

// https://gist.github.com/badboy/6267743
ulong hash64shift(ulong key)
{
	key = (~key) + (key << 21); // key = (key << 21) - key - 1;
	key = key ^ (key >> 24);
	key = (key + (key << 3)) + (key << 8); // key * 265
	key = key ^ (key >> 14);
	key = (key + (key << 2)) + (key << 4); // key * 21
	key = key ^ (key >> 28);
	key = key + (key << 31);
	return key;
}

uint hash32shift(uint key)
{
	key = ~key + (key << 15); // key = (key << 15) - key - 1;
	key = key ^ (key >> 12);
	key = key + (key << 2);
	key = key ^ (key >> 4);
	key = key * 2057; // key = (key + (key << 3)) + (key << 11);
	key = key ^ (key >> 16);
	return key;
}

uint getRngState(uint hostSeed, uint taskId)
{
	return hash32shift(hostSeed + taskId);
}

uint xorshift32(uint *state)
{
	uint x = *state;
	x ^= x << 13;
	x ^= x >> 17;
	x ^= x << 5;
	*state = x;
	return x;
}

ulong xorshift64(ulong *state)
{
	ulong x = *state;
	x ^= x << 13;
	x ^= x >> 7;
	x ^= x << 17;
	*state = x;
	return x;
}

float uniform01(uint *state)
{
	uint dice = xorshift32(state);
	return (float) dice / UINT_MAX;
}

float uniform(uint *state, float lower, float upper)
{
	float roll = uniform01(state);
	return roll * (upper - lower) + lower;
}

// Add uniform noise to each number in array
void __kernel addUniformNoise(
	__global float *data,
	const float amp,
	const uint seed)
{
	uint idx = get_global_id(0);
	uint randState = getRngState(seed, idx);
	float val = data[idx];
	val += uniform(&randState, -amp, amp);
	data[idx] = val;
}


/// Linearly interpolates intensity of the signal
void __kernel interpolateIntensity(
	__global float *tds,
	const float startMult,
	const float endMult)
{
	uint idx = get_global_id(0);
	uint len = get_global_size(0);
	float delta = endMult - startMult;
	float thisMult = startMult + delta * idx / (len - 1);
	tds[idx] = tds[idx] * sqrt(fabs(thisMult));
}


float trochoid(float A, float B, float C, float x)
{
	return A * sin(x + M_PI_2_F + B * sin(x) + C);
}

struct Harmonic
{
	float freqMult;
	float magnitude;
}

/// Modulate trochoid with time-domain signal
void __kernel modulateTrochoid(
	__global float *tds,
	__constant Harmonic *harmonics,		// [0.2f, 0.05f, 0.8f]
	const int harmonicCount,
	const float A,
	const float B,
	const float C,
	const float startFundFreq,
	const float endFundFreq,
	const float startPhase,
	const float energyIntegral)
{
	uint idx = get_global_id(0);
	uint len = get_global_size(0);
	const float linGain = 1.0f / sqrt(energyIntegral);
	const float dfreq = endFundFreq - startFundFreq;
	const float t = (float) idx / (len - 1);
	const float fundPhase = 2 * M_PI * (startFundFreq * t + 0.5f * dfreq * t * t);
	float modk = 1.0f;
	float result = tds[idx];
	for (int h = 0; h < harmonicCount; h++)
	{
		const Harmonic harm = harmonics[h];
		float phase = (startPhase + fundPhase) * harm.freqMult;
		modk += harm.magnitude * trochoid(A, B, C, phase);
	}
	result *= modk * linGain;
	tds[idx] = result;
}


// Return A*B
float2 cmul(float2 a, float2 b)
{
	return (float2)(
		a.x * b.x - a.y * b.y,
		a.x * b.y + a.y * b.x);
}

float2 fromPolar(float modulus, float arg)
{
	float cs, sn;
	sn = sincos(arg, &cs);
	return (float2)(modulus * cs, modulus * sn);
}

// Return A * exp(K*ALPHA*i)
float2 twiddle(float2 a, int k, float alpha)
{
	float cs, sn;
	sn = sincos((float)k * alpha, &cs);
	return cmul(a, (float2)(cs, sn));
}

/// Convert intensity (or intensity level) spectrum to pressure spectrum by
/// randomizing phases, and then prepare it for pure-real ifft.
void __kernel energyToPressure(
	__global const float *energyBins,
	__global float2 *pressureBins,
	const int isILevel,
	const uint seed)
{
	const uint binCount = get_global_size(0);
	const uint idx = get_global_id(0);
	const uint conjIdx = binCount - idx;
	uint randState1 = getRngState(seed, idx);
	uint randState2 = getRngState(seed, conjIdx);
	const uint N = binCount * 2;
	const float2 j = (float2)(0.0f, 1.0f);
	float phase1, phase2;
	float2 Xk1, Xk2, jw, res;

	// we have deterministic rng on gpu so we can regenerate the phase of conjIdx work item
	phase1 = uniform(&randState1, -M_PI, M_PI);
	phase2 = -uniform(&randState2, -M_PI, M_PI);

	float modulus1 = idx == 0 ? 0.0f : energyBins[idx - 1];
	float modulus2 = energyBins[conjIdx - 1];
	// convert from energy to pressure magnitude
	if (isILevel == 1)
	{
		modulus1 = toLinear(modulus1 / 2);
		modulus2 = toLinear(modulus2 / 2);
	}
	else
	{
		modulus1 = sqrt(modulus1);
		modulus2 = sqrt(modulus2);
	}
	Xk1 = fromPolar(modulus1, phase1);
	Xk2 = fromPolar(modulus2, phase2);
	jw = twiddle(j, 2, M_PI * idx / N);
	res = cmul(Xk1, (float2)(1.0f, 0.0f) + jw);
	res += cmul(Xk2, (float2)(1.0f, 0.0f) - jw);
	res *= 0.5f;
	pressureBins[idx] = res;
}

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


// void __kernel

// http://www.bealto.com/gpu-fft_fft.html

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

float2 itwiddle_1_2(float2 a) { return (float2)(-a.y, a.x); }

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
	iDFT4(u0, u1, u2, u3);

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