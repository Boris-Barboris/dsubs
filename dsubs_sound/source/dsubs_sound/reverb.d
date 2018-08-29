/// translation of https://github.com/highfidelity/gverb
module dsubs_sound.reverb;

import dsubs_sound.common;


enum FDNORDER = 4;


struct ty_gverb
{
	private
	{
		int rate;
		float inputbandwidth;
		float taillevel;
		float earlylevel;
		ty_damper inputdamper;
		float maxroomsize;
		float roomsize;
		float revtime;
		float maxdelay;
		float largestdelay;
		ty_fixeddelay[FDNORDER] fdndels;
		float[FDNORDER] fdngains;
		int[FDNORDER] fdnlens;
		ty_damper[FDNORDER] fdndamps;
		float fdndamping;
		ty_diffuser **ldifs;
		ty_diffuser **rdifs;
		ty_fixeddelay tapdelay;
		int[FDNORDER] taps;
		float[FDNORDER] tapgains;
		float[FDNORDER] d;
		float[FDNORDER] u;
		float[FDNORDER] f;
		double alpha;
	}

	void set_roomsize(const float a)
	{
		uint i;

		if (a <= 1.0 || (a != a))
			roomsize = 1.0f;
		else
			roomsize = a;
		largestdelay = rate * roomsize * 0.00294f;

		fdnlens[0] = lrint(1.000000f * largestdelay);
		fdnlens[1] = lrint(0.816490f * largestdelay);
		fdnlens[2] = lrint(0.707100f * largestdelay);
		fdnlens[3] = lrint(0.632450f * largestdelay);

		for(i = 0; i < FDNORDER; i++)
			fdngains[i] = -pow(alpha.to!float, fdnlens[i]);

		taps[0] = 5 + lrint(0.410f * largestdelay);
		taps[1] = 5 + lrint(0.300f * largestdelay);
		taps[2] = 5 + lrint(0.155f * largestdelay);
		taps[3] = 5 + lrint(0.0001f * largestdelay);

		for(i = 0; i < FDNORDER; i++)
			tapgains[i] = powf(alpha.to!float, taps[i]);
	}
}

private struct ty_damper
{
	float damping;
	float delay = 0.0f;

	this(float damping)
	{
		this.damping = damping;
	}

	void flush()
	{
		delay = 0.0f;
	}
}

private struct ty_fixeddelay
{
	int idx;
	float[] buf;

	this(int size)
	{
		buf.length = size;
		buf[] = 0.0f;
	}

	void flush()
	{
		buf[] = 0.0f;
	}
}

private void gverb_fdnmatrix(ref const float[4] a, ref float[4] b)
{
	const float dl0 = a[0], dl1 = a[1], dl2 = a[2], dl3 = a[3];

	b[0] = 0.5f * (+dl0 + dl1 - dl2 - dl3);
	b[1] = 0.5f * (+dl0 - dl1 - dl2 + dl3);
	b[2] = 0.5f * (-dl0 + dl1 - dl2 + dl3);
	b[3] = 0.5f * (+dl0 + dl1 + dl2 + dl3);
}

void gverb_do(ref ty_gverb p, float x, out float yl, out float yr)
{
	float z;
	uint i;
	float lsum, rsum, sum, sign;

	if ((x != x) || fabsf(x) > 100000.0f)
		x = 0.0f;

	z = damper_do(p.inputdamper, x);

	z = diffuser_do(p.ldifs[0], z);

	for(i = 0; i < FDNORDER; i++)
	{
		p.u[i] = p.tapgains[i] * fixeddelay_read(p.tapdelay, p.taps[i]);
	}
	fixeddelay_write(p.tapdelay, z);

	for(i = 0; i < FDNORDER; i++)
	{
		p.d[i] = damper_do(p.fdndamps[i],
			p.fdngains[i] * fixeddelay_read(p.fdndels[i], p.fdnlens[i]));
	}

	sum = 0.0f;
	sign = 1.0f;
	for(i = 0; i < FDNORDER; i++)
	{
		sum += sign * (p.taillevel * p.d[i] + p.earlylevel * p.u[i]);
		sign = -sign;
	}
	sum += x * p.earlylevel;
	lsum = sum;
	rsum = sum;

	gverb_fdnmatrix(p.d, p.f);

	for(i = 0; i < FDNORDER; i++)
	{
		fixeddelay_write(p.fdndels[i], p.u[i] + p.f[i]);
	}

	lsum = diffuser_do(p.ldifs[1], lsum);
	lsum = diffuser_do(p.ldifs[2], lsum);
	lsum = diffuser_do(p.ldifs[3], lsum);
	rsum = diffuser_do(p.rdifs[1], rsum);
	rsum = diffuser_do(p.rdifs[2], rsum);
	rsum = diffuser_do(p.rdifs[3], rsum);

	yl = lsum;
	yr = rsum;
}