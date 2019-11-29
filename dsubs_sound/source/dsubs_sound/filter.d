module dsubs_sound.filter;

import std.algorithm;
import std.array;
import std.csv;
import std.range;
import std.traits;
import std.stdio;
import std.string: strip;

import core.time;

import derelict.opencl.constants;

import dsubs_sound.common;
import dsubs_sound.spectrum;
import dsubs_sound.opencl;
import dsubs_sound.wav;


/// OpenCL linear time-domain filter
struct FIRFilter
{
	this(CommandQueue q, immutable(float)[] taps)
	{
		m_tapCount = taps.length.to!int;
		m_taps = Buffer(q, taps, CL_MEM_READ_ONLY);
	}

	@disable this(this);

	private
	{
		Buffer m_taps;
		int m_tapCount;
	}

	@property int tapCount() const { return m_tapCount; }

	void filter(CommandQueue q, ref Tds prev, ref Tds cur, ref Tds dest)
	{
		Kernel k = q.mk_firTds;
		k.setArg(0, cur.mem);
		k.setArg(1, prev.mem);
		k.setArg(2, m_taps.mem);
		k.setArg(3, m_tapCount);
		k.setArg(4, dest.mem);
		k.enqueue(q, 1, null, [GLOBAL_SRATE], null, null);
	}

	void filter(CommandQueue q, ref VarTds prev, ref VarTds cur, ref VarTds dest)
	{
		Kernel k = q.mk_firTds;
		k.setArg(0, cur.mem);
		k.setArg(1, prev.mem);
		k.setArg(2, m_taps.mem);
		k.setArg(3, m_tapCount);
		k.setArg(4, dest.mem);
		k.enqueue(q, 1, null, [cur.length], null, null);
	}

	void filter(CommandQueue q, ref VarTds cur, size_t curOffset, size_t destOffset,
		ref Tds dest)
	{
		assert(destOffset <= dest.BUF_LEN);
		assert(curOffset <= cur.length);
		Kernel k = q.mk_firTds2;
		k.setArg(0, cur.mem);
		k.setArg(1, curOffset.to!int - destOffset.to!int);
		k.setArg(2, m_taps.mem);
		k.setArg(3, m_tapCount);
		k.setArg(4, dest.mem);
		k.enqueue(q, 1, [destOffset],
			[min(dest.BUF_LEN - destOffset, cur.length - curOffset)], null, null);
	}

	void filter(CommandQueue q, ref VarTds cur, size_t curOffset, size_t destOffset,
		ref VarTds dest)
	{
		assert(destOffset <= dest.length);
		assert(curOffset <= cur.length);
		Kernel k = q.mk_firTds2;
		k.setArg(0, cur.mem);
		k.setArg(1, curOffset.to!int - destOffset.to!int);
		k.setArg(2, m_taps.mem);
		k.setArg(3, m_tapCount);
		k.setArg(4, dest.mem);
		k.enqueue(q, 1, [destOffset],
			[min(dest.length - destOffset, cur.length - curOffset)], null, null);
	}
}


WaterFIRFilter loadWaterFilterFromFile(CommandQueue q, string csvContents,
	float maxRange, float dissk)
{
	auto records = csvContents.strip.csvReader!float();
	float[][] mat = records.map!(row => row.array).array;
	WaterFIRFilter res = WaterFIRFilter(q, mat, maxRange, dissk);
	return res;
}

/// FIR filter that simulates water-like lowpass filter with a table of
/// gains that can be interpolated between based on target range.
struct WaterFIRFilter
{
	this(CommandQueue q, float[][] tapMatrix,
		float maxRange, float dissK)
	{
		m_tapCount = tapMatrix[0].length.to!int;
		m_maxRange = maxRange;
		m_inbuiltDissk = dissK;
		m_bufferCount = tapMatrix.length.to!int;
		m_tapBufs.length = m_bufferCount;
		for (int i = 0; i < m_bufferCount; i++)
		{
			assert(tapMatrix[i].length == m_tapCount);
			m_tapBufs[i] = Buffer(q, tapMatrix[i], CL_MEM_READ_ONLY);
		}
	}

	@disable this(this);

	@property int tapCount() const { return m_tapCount; }

	private
	{
		Buffer[] m_tapBufs;
		int m_tapCount;
		int m_bufferCount;
		float m_maxRange;
		float m_inbuiltDissk;
	}

	void filter(DestBufT)(CommandQueue q, ref VarTds cur, size_t curOffset,
		ref DestBufT dest, size_t destOffset, float rangeStart, float rangeEnd,
		float rangeDissK = 4.0f)
	{
		assert(rangeStart >= 0.0f);
		assert(rangeEnd >= 0.0f);
		float normRange1 = rangeStart * rangeDissK / m_inbuiltDissk;
		float normRange2 = rangeEnd * rangeDissK / m_inbuiltDissk;
		int startIdx, endIdx;
		float tap1WeightStart, tap1WeightEnd;
		if (normRange1 <= normRange2)
		{
			startIdx = max(0, min(m_bufferCount - 1,
				floor(m_bufferCount * normRange1 / m_maxRange).to!int));
			endIdx = max(0, min(m_bufferCount - 1,
				ceil(m_bufferCount * normRange2 / m_maxRange).to!int));
		}
		else
		{
			startIdx = max(0, min(m_bufferCount - 1,
				ceil(m_bufferCount * normRange1 / m_maxRange).to!int));
			endIdx = max(0, min(m_bufferCount - 1,
				floor(m_bufferCount * normRange2 / m_maxRange).to!int));
		}
		if (startIdx == endIdx)
		{
			tap1WeightStart = 1.0f;
			tap1WeightEnd = 1.0f;
		}
		else
		{
			float borderStartRange = startIdx * m_maxRange / (m_bufferCount - 1);
			float borderEndRange = endIdx * m_maxRange / (m_bufferCount - 1);
			float span = borderEndRange - borderStartRange;
			assert(span != 0.0f);
			tap1WeightStart = max(0.0f, min(1.0f,
				1.0f - (normRange1 - borderStartRange) / span));
			tap1WeightEnd = max(0.0f, min(1.0f,
				(borderEndRange - normRange2) / span));
		}
		assert(!isNaN(tap1WeightStart));
		assert(!isNaN(tap1WeightEnd));
		Kernel k = q.mk_firTdsTwoFilters;
		k.setArg(0, cur.mem);
		k.setArg(1, m_tapBufs[startIdx].mem);
		k.setArg(2, m_tapBufs[endIdx].mem);
		k.setArg(3, m_tapCount);
		k.setArg(4, curOffset.to!int);
		k.setArg(5, tap1WeightStart);
		k.setArg(6, tap1WeightEnd);
		k.setArg(7, dest.mem);
		k.setArg(8, destOffset.to!int);
		static if (is(DestBufT == Tds))
		{
			k.setArg(9, dest.BUF_LEN.to!int);
			k.enqueue(q, 1, null,
				[min(cur.length - curOffset, dest.BUF_LEN - destOffset)], null, null);
		}
		else if (is(DestBufT == VarTds))
		{
			k.setArg(9, dest.length.to!int);
			k.enqueue(q, 1, null,
				[min(cur.length - curOffset, dest.length - destOffset)], null, null);
		}
	}
}

unittest
{
	float[] noise = new float[GLOBAL_SRATE * 4];
	for (int i = 0; i < noise.length; i++)
		noise[i] = uniform(-1.0f, 1.0f);
	CommandQueue q = s_clCtx.queue(0);
	VarTds tds = VarTds(q, noise);
	VarTds destTds = VarTds(q, noise.length, 0.0f);
	s_clCtx.waterFilter.filter(q, tds, 0,
		destTds, 0, 0.0f, 50000.0f, 4.0f);
	destTds.read(q, noise);
	writeWavFile("whitenoise_water_filtered.wav", noise, 1.0f);
}

// 8192 sampling rate filters:

immutable float[] octaveHp250 = [
	0.00101834829399173,0.001090247722271315,0.001217332984952719,0.00137546883992344,0.001518287771796139,0.001578458852957172,0.001471163556424477,0.00109962027761624,0.0003623115008542797,-0.0008385977611798445,-0.00258828951813959,-0.004950488022214052,-0.007959559162071904,-0.0116142123706823,-0.01587340393654331,-0.02065488862131024,-0.02583667327621875,-0.03126140670333281,-0.03674351177886176,-0.04207864732591535,-0.04705489636094709,-0.05146493008167403,-0.05511830586906283,-0.05785303072864253,-0.05954556190196968,0.940879296452775,-0.05954556190196967,-0.05785303072864254,-0.05511830586906283,-0.05146493008167403,-0.0470548963609471,-0.04207864732591536,-0.03674351177886176,-0.03126140670333279,-0.02583667327621874,-0.02065488862131025,-0.01587340393654331,-0.01161421237068231,-0.007959559162071909,-0.004950488022214055,-0.002588289518139591,-0.0008385977611798452,0.0003623115008542796,0.001099620277616241,0.001471163556424478,0.001578458852957172,0.001518287771796142,0.00137546883992344,0.001217332984952719,0.001090247722271315,0.00101834829399173
];

immutable float[] octaveHp200 = [
	0.0005900207170913992,0.0004994523819777912,0.0004068230624962287,0.0002683371550917839,3.187219457917165e-05,-0.0003599815123919743,-0.0009662913840764116,-0.001843773299028035,-0.003042645085410451,-0.004602602886567918,-0.006549181854226746,-0.008890747230388133,-0.01161633040998788,-0.01469447872510303,-0.01807323011359502,-0.0216812579848517,-0.02543016151032353,-0.0292178066119669,-0.03293255751033296,-0.0364581820008926,-0.03967916931713195,-0.04248617042559144,-0.04478125884991957,-0.04648271652832816,-0.04752907351939948,0.9527574881756061,-0.04752907351939948,-0.04648271652832817,-0.04478125884991957,-0.04248617042559144,-0.03967916931713197,-0.03645818200089262,-0.03293255751033296,-0.02921780661196688,-0.02543016151032352,-0.02168125798485171,-0.01807323011359502,-0.01469447872510304,-0.01161633040998789,-0.008890747230388137,-0.00654918185422675,-0.004602602886567922,-0.003042645085410449,-0.001843773299028036,-0.0009662913840764126,-0.0003599815123919747,3.187219457917189e-05,0.0002683371550917838,0.0004068230624962289,0.0004994523819777914,0.000590020717091399
];

immutable float[] octaveBp1900_2500 = [
	0.0003071137765103841,0.00139270978842752,-0.001102722454800399,-0.002431804876855447,0.002821781811224755,0.00340701286420224,-0.00536748460334891,-0.003331826428533371,0.007141959986434977,0.001705270007482565,-0.005089053027964544,-3.017986048899921e-05,-0.003721278908490984,0.002314724137341588,0.01965630116454797,-0.01361912465689843,-0.03886370604984939,0.03701942979298068,0.05390098640433504,-0.07068508617823799,-0.05686788370102198,0.1071043782591406,0.04357459089532952,-0.135443895089199,-0.0163499138044498,0.1461556073243368,-0.0163499138044498,-0.135443895089199,0.04357459089532952,0.1071043782591406,-0.05686788370102198,-0.070685086178238,0.05390098640433504,0.03701942979298067,-0.03886370604984938,-0.01361912465689844,0.01965630116454797,0.002314724137341588,-0.003721278908490986,-3.017986048899859e-05,-0.005089053027964547,0.001705270007482566,0.007141959986434976,-0.003331826428533374,-0.005367484603348913,0.003407012864202241,0.002821781811224759,-0.002431804876855447,-0.001102722454800399,0.001392709788427521,0.0003071137765103843
];

immutable float[] octaveHp3500 = [
	0.0008895017693282614,-0.001108192884008094,0.001198853049918372,-0.001046810712144222,0.0004922197121350511,0.0005858473275367584,-0.002161209844236898,0.003972250850232683,-0.005500193546094496,0.006046248974717272,-0.004910762497931523,0.001641614908216096,0.003712335693458722,-0.01042302702872873,0.01705368913446635,-0.02162101482651102,0.0219438094284972,-0.01611939409056642,0.003025122950353519,0.01727835926087336,-0.04335500517688493,0.07248376022890009,-0.1010391304378595,0.1250992350193627,-0.1411598035481207,0.1468010993182979,-0.1411598035481207,0.1250992350193627,-0.1010391304378595,0.07248376022890007,-0.04335500517688495,0.01727835926087336,0.003025122950353518,-0.01611939409056641,0.0219438094284972,-0.02162101482651102,0.01705368913446635,-0.01042302702872873,0.003712335693458724,0.001641614908216097,-0.004910762497931524,0.006046248974717278,-0.005500193546094493,0.003972250850232687,-0.002161209844236899,0.0005858473275367583,0.0004922197121350517,-0.001046810712144222,0.001198853049918372,-0.001108192884008095,0.0008895017693282612
];