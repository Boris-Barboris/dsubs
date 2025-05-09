/*
DSubs
Copyright (C) 2017-2025 Baranin Alexander

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

/// manual translation of https://github.com/highfidelity/gverb
module dsubs_sound.reverb;

import dsubs_sound.common;


private enum FDNORDER = 4;


struct GverbParams
{
	int srate;
	float maxroomsize;
	float roomsize;
	float revtime;
	float damping;
	float spread;
	float inputbandwidth;
	float earlylevel;
	float taillevel;
}

struct TyGverb
{
	private
	{
		int rate;
		float inputbandwidth;
		float taillevel;
		float earlylevel;
		TyDamper inputdamper;
		float maxroomsize;
		float roomsize;
		float revtime;
		float maxdelay;
		float largestdelay;
		TyFixeddelay[FDNORDER] fdndels;
		float[FDNORDER] fdngains;
		int[FDNORDER] fdnlens;
		TyDamper[FDNORDER] fdndamps;
		float fdndamping;
		TyDiffuser[FDNORDER] ldifs;
		TyDiffuser[FDNORDER] rdifs;
		TyFixeddelay tapdelay;
		int[FDNORDER] taps;
		float[FDNORDER] tapgains;
		float[FDNORDER] d;
		float[FDNORDER] u;
		float[FDNORDER] f;
		double alpha;
	}

	this(ref const GverbParams p)
	{
		float ga, gb, gt;
		int i, n;
		float r;
		float diffscale;
		int a, b, c, cc, d, dd, e;
		float spread1, spread2;

		rate = p.srate;
		fdndamping = p.damping;
		maxroomsize = p.maxroomsize;
		roomsize = p.roomsize;
		revtime = p.revtime;
		earlylevel = p.earlylevel;
		taillevel = p.taillevel;

		maxdelay = rate * maxroomsize / 340.0;

		/* Input damper */

		inputbandwidth = p.inputbandwidth;
		inputdamper = TyDamper(1.0 - inputbandwidth);

		/* FDN section */

		for(i = 0; i < FDNORDER; i++)
		{
			fdndels[i] = TyFixeddelay(maxdelay.to!int + 1000);
			fdndamps[i] = TyDamper(fdndamping);
		}

		ga = 60.0;
		gt = revtime;
		ga = pow(10.0f, -ga / 20.0f);
		n = (rate * gt).to!int;
		alpha = pow(ga, 1.0 / n);

		set_roomsize(roomsize);

		/* Diffuser section */

		diffscale = fdnlens[3] / cast(float)(210 + 159 + 562 + 410);
		spread1 = p.spread;
		spread2 = 3.0 * p.spread;

		b = 210;
		r = 0.125541;
		a = (spread1 * r).to!int;
		c = 210 + 159 + a;
		cc = c - b;
		r = 0.854046;
		a = (spread2 * r).to!int;
		d = 210 + 159 + 562 + a;
		dd = d - c;
		e = 1341 - d;

		ldifs[0] = TyDiffuser((diffscale * b).to!int, 0.75);
		ldifs[1] = TyDiffuser((diffscale * cc).to!int, 0.75);
		ldifs[2] = TyDiffuser((diffscale * dd).to!int, 0.625);
		ldifs[3] = TyDiffuser((diffscale * e).to!int, 0.625);

		b = 210;
		r = -0.568366;
		a = (spread1 * r).to!int;
		c = 210 + 159 + a;
		cc = c - b;
		r = -0.126815;
		a = (spread2 * r).to!int;
		d = 210 + 159 + 562 + a;
		dd = d - c;
		e = 1341 - d;

		rdifs[0] = TyDiffuser((diffscale * b).to!int, 0.75);
		rdifs[1] = TyDiffuser((diffscale * cc).to!int, 0.75);
		rdifs[2] = TyDiffuser((diffscale * dd).to!int, 0.625);
		rdifs[3] = TyDiffuser((diffscale * e).to!int, 0.625);

		/* Tapped delay section */

		tapdelay = TyFixeddelay(rate);
	}

	void set_roomsize(float a)
	{
		uint i;

		if (a <= 1.0 || (a != a))
			roomsize = 1.0f;
		else
			roomsize = a;
		largestdelay = rate * roomsize * 0.00294f;

		fdnlens[0] = lrint(1.000000f * largestdelay).to!int;
		fdnlens[1] = lrint(0.816490f * largestdelay).to!int;
		fdnlens[2] = lrint(0.707100f * largestdelay).to!int;
		fdnlens[3] = lrint(0.632450f * largestdelay).to!int;

		for(i = 0; i < FDNORDER; i++)
			fdngains[i] = -pow(alpha.to!float, fdnlens[i]);

		taps[0] = 5 + lrint(0.410f * largestdelay).to!int;
		taps[1] = 5 + lrint(0.300f * largestdelay).to!int;
		taps[2] = 5 + lrint(0.155f * largestdelay).to!int;
		taps[3] = 5 + lrint(0.0001f * largestdelay).to!int;

		for(i = 0; i < FDNORDER; i++)
			tapgains[i] = pow(alpha.to!float, taps[i]);
	}


	void set_revtime(float a)
	{
		if (a == revtime)
			return;

		float ga, gt;
		double n;
		uint i;

		revtime = a;

		ga = 60.0;
		gt = revtime;
		ga = pow(10.0f, -ga/20.0f);
		n = rate * gt;
		alpha = pow(ga, 1.0f / n).to!double;

		for(i = 0; i < FDNORDER; i++)
			fdngains[i] = -pow(alpha.to!float, fdnlens[i]);
	}

	private void set_damping(float a)
	{
		uint i;

		fdndamping = a;
		for(i = 0; i < FDNORDER; i++)
			fdndamps[i].damping = fdndamping;
	}

	private void set_inputbandwidth(float a)
	{
		inputbandwidth = a;
		inputdamper.damping = 1.0 - inputbandwidth;
	}

	void flush()
	{
		inputdamper.flush();
		for(int i = 0; i < FDNORDER; i++)
		{
			fdndels[i].flush();
			fdndamps[i].flush();
			ldifs[i].flush();
			rdifs[i].flush();
		}
		d[] = 0.0f;
		u[] = 0.0f;
		f[] = 0.0f;
		tapdelay.flush();
	}

	void run(float x, out float yl, out float yr)
	{
		float z;
		uint i;
		float lsum, rsum, sum, sign;

		if ((x != x) || fabs(x) > 100000.0f)
		{
			assert(0, "floating shenanigans, should not happen");
			//x = 0.0f;
		}

		z = inputdamper.run(x);

		z = ldifs[0].run(z);

		for(i = 0; i < FDNORDER; i++)
			u[i] = tapgains[i] * tapdelay.read(taps[i]);
		tapdelay.write(z);

		for(i = 0; i < FDNORDER; i++)
		{
			d[i] = fdndamps[i].run(
				fdngains[i] * fdndels[i].read(fdnlens[i]));
		}

		sum = 0.0f;
		sign = 1.0f;
		for(i = 0; i < FDNORDER; i++)
		{
			sum += sign * (taillevel * d[i] + earlylevel * u[i]);
			sign = -sign;
		}
		sum += x * earlylevel;
		lsum = sum;
		rsum = sum;

		gverb_fdnmatrix(d, f);

		for(i = 0; i < FDNORDER; i++)
			fdndels[i].write(u[i] + f[i]);

		lsum = ldifs[1].run(lsum);
		lsum = ldifs[2].run(lsum);
		lsum = ldifs[3].run(lsum);
		rsum = rdifs[1].run(rsum);
		rsum = rdifs[2].run(rsum);
		rsum = rdifs[3].run(rsum);

		yl = lsum;
		yr = rsum;
	}

	void runMono(float x, out float yl)
	{
		float z;
		uint i;
		float lsum, sum, sign;

		if ((x != x) || fabs(x) > 100000.0f)
		{
			assert(0, "floating shenanigans, should not happen");
			//x = 0.0f;
		}

		z = inputdamper.run(x);

		z = ldifs[0].run(z);

		for(i = 0; i < FDNORDER; i++)
			u[i] = tapgains[i] * tapdelay.read(taps[i]);
		tapdelay.write(z);

		for(i = 0; i < FDNORDER; i++)
		{
			d[i] = fdndamps[i].run(
				fdngains[i] * fdndels[i].read(fdnlens[i]));
		}

		sum = 0.0f;
		sign = 1.0f;
		for(i = 0; i < FDNORDER; i++)
		{
			sum += sign * (taillevel * d[i] + earlylevel * u[i]);
			sign = -sign;
		}
		sum += x * earlylevel;
		lsum = sum;

		gverb_fdnmatrix(d, f);

		for(i = 0; i < FDNORDER; i++)
			fdndels[i].write(u[i] + f[i]);

		lsum = ldifs[1].run(lsum);
		lsum = ldifs[2].run(lsum);
		lsum = ldifs[3].run(lsum);

		yl = lsum;
	}

	void applyToBuf(float[] x, ref float[] res)
	{
		res.length = x.length;
		for (size_t i = 0; i < x.length; i++)
			runMono(x[i], res[i]);
	}
}

private struct TyDamper
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

	float run(float x)
	{
		delay = x * (1.0f - damping) + delay * damping;
		return delay;
	}
}

private struct TyDiffuser
{
	int size;
	float coeff;
	int idx;
	float[] buf;

	this(int size, float coeff)
	{
		this.size = size;
		this.coeff = coeff;
		buf.length = size;
		buf[] = 0.0f;
	}

	void flush()
	{
		idx = 0;
		buf[] = 0.0f;
	}

	float run(float x)
	{
		float y, w;
		w = x - buf[idx] * coeff;
		y = buf[idx] + w * coeff;
		buf[idx] = w;
		idx = (idx + 1) % size;
		return y;
	}
}

private struct TyFixeddelay
{
	int idx;
	int size;
	float[] buf;

	this(int size)
	{
		this.size = size;
		buf.length = size;
		buf[] = 0.0f;
	}

	void flush()
	{
		buf[] = 0.0f;
	}

	float read(int n)
	{
		int i = (idx - n + size) % size;
		return buf[i];
	}

	void write(float x)
	{
		buf[idx] = x;
		idx = (idx + 1) % size;
	}
}

private void gverb_fdnmatrix(ref const float[FDNORDER] a, ref float[FDNORDER] b)
{
	const float dl0 = a[0], dl1 = a[1], dl2 = a[2], dl3 = a[3];

	b[0] = 0.5f * (+dl0 + dl1 - dl2 - dl3);
	b[1] = 0.5f * (+dl0 - dl1 - dl2 + dl3);
	b[2] = 0.5f * (-dl0 + dl1 - dl2 + dl3);
	b[3] = 0.5f * (+dl0 + dl1 + dl2 + dl3);
}