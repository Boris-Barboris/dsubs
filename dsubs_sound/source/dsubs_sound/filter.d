module dsubs_sound.filter;

import std.algorithm;
import std.range;
import std.traits;
import std.stdio: writeln;

import core.time;

import dsubs_sound.common;


/*
FIR filter designed with
http://t-filter.appspot.com
*/

private immutable float[] tapsHp500 = [
	-0.016233494320316448,
	0.06120383335803086,
	-0.053661059585354366,
	-0.02464926643968014,
	0.01503612591550853,
	0.029790698863917487,
	0.02002511551379012,
	-0.003462331796939165,
	-0.025589033243486863,
	-0.032476199750519255,
	-0.016864590696685687,
	0.016047019240079133,
	0.04791617068119353,
	0.0542971834338357,
	0.01773352498933556,
	-0.060360844164256,
	-0.15724063750277026,
	-0.23726188567967738,
	0.7317838840616425,
	-0.23726188567967738,
	-0.15724063750277026,
	-0.060360844164256,
	0.01773352498933556,
	0.0542971834338357,
	0.04791617068119353,
	0.016047019240079133,
	-0.016864590696685687,
	-0.032476199750519255,
	-0.025589033243486863,
	-0.003462331796939165,
	0.02002511551379012,
	0.029790698863917487,
	0.01503612591550853,
	-0.02464926643968014,
	-0.053661059585354366,
	0.06120383335803086,
	-0.016233494320316448,
];

private immutable float[] octaveHp500 =
	[  0.00112812,  0.00120991,  0.00043872, -0.00121064, -0.00295939, -0.00311903, -0.00023075,  0.00504615,  0.00908985,  0.00714533, -0.00259118 ,
  -0.01557452, -0.02179484, -0.01205388,  0.01360779,  0.04151048,  0.04879799,  0.01605565, -0.05887064, -0.15509111, -0.23615412,  0.73308645 ,
  -0.23615412, -0.15509111, -0.05887064,  0.01605565,  0.04879799,  0.04151048,  0.01360779, -0.01205388, -0.02179484, -0.01557452, -0.00259118 ,
   0.00714533,  0.00908985,  0.00504615, -0.00023075, -0.00311903, -0.00295939, -0.00121064,  0.00043872,  0.00120991,  0.00112812 ];

private immutable float[] octaveHp500Small =
[ -0.0021707, -0.0034806, -0.0028594,  0.0047680,  0.0199879,  0.0300598,  0.0119118, -0.0500182, -0.1445141, -0.2321849, 0.7335775, -0.2321849,
  -0.1445141, -0.0500182,  0.0119118,  0.0300598,  0.0199879,  0.0047680, -0.0028594, -0.0034806, -0.0021707 ];

immutable LinearFIR highpass500 = immutable LinearFIR(octaveHp500Small);


struct LinearFIR
{
	private immutable(float)[] taps;

	void filter(RS, RD)(RS sourceSignal, RD destSignal) const
		if (is(Unqual!(ElementType!RS) == float) &&
			is(Unqual!(ElementType!RD) == float))
	{
		// auto before = MonoTime.currTime;
		for (ptrdiff_t i = 0; i < destSignal.length; i++)
			destSignal[i] = iota(0, ptrdiff_t(taps.length)).map!(
				j => sourceSignal[i - j] * taps[j]).sum;
		// auto after = MonoTime.currTime;
		// writeln("FIR filtering performed in ", after - before);
	}
}



private immutable float[] butter500HPa =
	[1.000000000, -6.202556958, 19.331798969, -39.380932123, 58.041558721,
	-65.106911798, 57.136128940, -39.792788938, 22.108417386, -9.774701341,
	3.404040204, -0.915399188, 0.183730793, -0.025950583, 0.002303776, -0.000096808 ];
private immutable float[] butter500HPb =
	[0.0098391, -0.1475864, 1.0331045, -4.4767862, 13.4303585, -29.5467887,
	49.2446478, -63.3145472, 63.3145472, -49.2446478, 29.5467887, -13.4303585,
	4.4767862, -1.0331045, 0.1475864, -0.0098391 ];

immutable LinearIIR highpass500butter = immutable LinearIIR(butter500HPa, butter500HPb);


struct LinearIIR
{
	private immutable(float)[] a;
	private immutable(float)[] b;

	void filter(RS, RD)(RS sourceSignal, RD destSignal, ptrdiff_t len) const
		if (is(Unqual!(ElementType!RS) == float) &&
			is(Unqual!(ElementType!RD) == float))
	{
		for (ptrdiff_t i = 0; i < len; i++)
		{
			destSignal[i] =
				(iota(0, ptrdiff_t(b.length)).map!(
					j => sourceSignal[i - j] * b[j]).sum -
				iota(1, ptrdiff_t(a.length)).map!(
					j => destSignal[i - j] * a[j]).sum) / a[0];
			assert(!isNaN(destSignal[i]));
		}
	}
}


auto cycled(R)(R r)
	if (isRandomAccessRange!R)
{
	static struct Cycled
	{
		private
		{
			R _r;
			ptrdiff_t idx, len;
		}

		this(R mr, ptrdiff_t idx)
		{
			_r = mr;
			this.idx = idx;
			len = _r.length.to!ptrdiff_t;
		}

		@property ref auto front()
		{
			return _r[idx];
		}

		enum bool empty = false;

		void popFront()
		{
			idx = (idx + 1) % len;
		}

		ref auto opIndex(ptrdiff_t n)
		{
			n = (n + idx) % len;
			if (n < 0)
				n = len + n;
			return _r[n];
		}

		void opIndexAssign(ElementType!R val, ptrdiff_t n)
		{
			n = (n + idx) % len;
			if (n < 0)
				n = len + n;
			_r[n] = val;
		}
	}

	return Cycled(r, 0);
}