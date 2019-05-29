module dsubs_sound.filter;

import std.algorithm;
import std.range;
import std.traits;
import std.stdio: writeln;

import core.time;

import dsubs_sound.common;
import dsubs_sound.spectrum;
import dsubs_sound.opencl;


/// OpenCL linear time-domain filter
struct LinearFilter
{
	this(CommandQueue q, immutable(float)[] taps)
	{
		m_tapCount = taps.length.to!int;
		m_taps = Buffer(q, taps);
	}

	@disable this(this);

	private
	{
		Buffer m_taps;
		int m_tapCount;
	}

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
}

// 8192 sampling rate filters:

immutable float[] octaveHp250 = [
	0.00101834829399173,0.001090247722271315,0.001217332984952719,0.00137546883992344,0.001518287771796139,0.001578458852957172,0.001471163556424477,0.00109962027761624,0.0003623115008542797,-0.0008385977611798445,-0.00258828951813959,-0.004950488022214052,-0.007959559162071904,-0.0116142123706823,-0.01587340393654331,-0.02065488862131024,-0.02583667327621875,-0.03126140670333281,-0.03674351177886176,-0.04207864732591535,-0.04705489636094709,-0.05146493008167403,-0.05511830586906283,-0.05785303072864253,-0.05954556190196968,0.940879296452775,-0.05954556190196967,-0.05785303072864254,-0.05511830586906283,-0.05146493008167403,-0.0470548963609471,-0.04207864732591536,-0.03674351177886176,-0.03126140670333279,-0.02583667327621874,-0.02065488862131025,-0.01587340393654331,-0.01161421237068231,-0.007959559162071909,-0.004950488022214055,-0.002588289518139591,-0.0008385977611798452,0.0003623115008542796,0.001099620277616241,0.001471163556424478,0.001578458852957172,0.001518287771796142,0.00137546883992344,0.001217332984952719,0.001090247722271315,0.00101834829399173
];