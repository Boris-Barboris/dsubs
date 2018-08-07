module dsubs_sound.filter;

import std.algorithm;
import std.range;
import std.traits;

import dsubs_sound.common;


/*
FIR filter designed with
http://t-filter.appspot.com
*/

static immutable float[] tapsHp500 = [
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

immutable LinearFIR highpass500 = immutable LinearFIR(tapsHp500);


struct LinearFIR
{
	private immutable(float)[] taps;

	void filter(RU, RD)(RU sourceSignal, RD destSignal) const
		if (is(Unqual!(ElementType!RU) == Complex!float) &&
			isRandomAccessRange!RD && is(Unqual!(ElementType!RD) == Complex!float))
	{
		if (taps.length == 0)
		{
			for (size_t i = 0; i < destSignal.length; i++)
				destSignal[i] = sourceSignal[i];
		}
		else
		{
			for (size_t i = 0; i < destSignal.length; i++)
				destSignal[i].re = iota(0, taps.length).map!(
					j => sourceSignal[i - j].re * taps[j]).sum;
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
			idx = (idx + 1) % _r.length;
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