module dsubs_sound.modulation;

import dsubs_sound.common;
import dsubs_sound.spectrum;
import dsubs_sound.opencl;


/// Linearly interpolate intensity of 'tds' signal inline
void modulateIInterp(CommandQueue q, ref Tds tds, float startMult, float endMult)
{
	Kernel k = q.interpolateIntensity;
	k.setArg(0, tds.mem);
	k.setArg(1, startMult);
	k.setArg(2, endMult);
	k.enqueue(q, 1, null, [tds.BUF_LEN], null, null).release();
}

struct Harmonic
{
	float freqMult = 1.0f;
	float magnitude = 0.0f;
}

/// 1.0 + A * sin(x + PI_2 + B * sin(x) + C)
struct TrochoidModulatorParams
{
	private
	{
		float A = 0.0f;
		float B = 0.0f;
		float C = 0.0f;
		immutable(Harmonic)[] harmonics;
		float energyIntegral = 1.0f;
	}

	this(immutable(Harmonic)[] harmonics,
		float A, float B, float C)
	{
		this.harmonics = harmonics;
		this.A = A;
		this.B = B;
		this.C = C;
		calculateIntegral(40);
	}

	private float get(float x) const
	{
		return A * sin(x + PI_2 + B * sin(x) + C);
	}

	private void calculateIntegral(int resolution = 40)
	{
		assert(resolution > 0);
		energyIntegral = 0.0f;
		float dt = PI * 2 / resolution;
		for (int i = 0; i < resolution; i++)
		{
			float val = 1.0f;
			for (int j = 0; j < harmonics.length; j++)
			{
				float phase = dt * i * harmonics[j].freqMult;
				val += harmonics[j].magnitude * get(phase);
			}
			assert(val >= 0.0f);
			energyIntegral += pow(val, 2);
		}
		energyIntegral /= resolution;
		assert(energyIntegral > 0.0f, "non-positive energy for modulator");
	}
}

/// 1.0 + A * sin(x + PI_2 + B * sin(x) + C)
struct TrochoidModulator
{
	private
	{
		float startPhase = 0.0f;
		float startFundFreq = 0.0f;
		float endFundFreq = 0.0f;
		immutable(TrochoidModulatorParams)* params;
	}

	this(immutable(TrochoidModulatorParams)* p, float startPhase = 0.0f)
	{
		this.params = p;
		this.startPhase = startPhase;
	}

	void modulate(CommandQueue q, ref Tds tds)
	{
		Buffer harmBuf = Buffer(q, params.harmonics);
		Kernel k = q.modulateTrochoid;
		k.setArg(0, tds.mem);
		k.setArg(1, harmBuf.mem);
		k.setArg(2, params.harmonics.length.to!int);
		k.setArg(3, params.A);
		k.setArg(4, params.B);
		k.setArg(5, params.C);
		k.setArg(6, startFundFreq);
		k.setArg(7, endFundFreq);
		k.setArg(8, startPhase);
		k.setArg(9, params.energyIntegral);
		k.enqueue(q, 1, null, [tds.BUF_LEN], null, null).release();
	}

	/// Set starting and ending fundamental frequencies
	void updateFundFreq(float start, float end)
	{
		startFundFreq = start;
		endFundFreq = end;
	}

	/// Rollover endFundFreq to start, update end
	void rolloverFundFreq(float newFreq)
	{
		startFundFreq = endFundFreq;
		endFundFreq = newFreq;
	}

	/// move startPhase forward as if a time interval has passed
	void updateStartPhase(float time)
	{
		startPhase += 2 * PI * (startFundFreq * time +
			0.5f * (endFundFreq - startFundFreq) * time * time);
		startPhase = fmod(startPhase, 2 * PI);
	}

	void randomizePhase()
	{
		startPhase = uniform(0.0f, float(2 * PI));
		startPhase = fmod(startPhase, 2 * PI);
	}
}


version (unittest)
{

	immutable(TrochoidModulatorParams) stdTrochParams()
	{
		return cast(immutable) TrochoidModulatorParams([
			Harmonic(1.0f, 0.2f),
			Harmonic(5.0f, 0.8f)],
			0.5, 0.7, -0.4);
	}

}


unittest
{
	import dsubs_sound.wav;

	auto ctx = s_clCtx;
	CommandQueue q = ctx.queue(0);
	ISpectrum spec = ISpectrum(q, 1.0f);
	spec.patch(q, 0.0f, 0, 200);
	Tds tds = Tds(ctx);
	spec.toTimeDomain(q, tds);
	auto tmParams = stdTrochParams();
	trace("tmParams: ", tmParams);
	TrochoidModulator tm = TrochoidModulator(&tmParams);
	tm.updateFundFreq(0.5f, 2.0f);
	tm.modulate(q, tds);
	modulateIInterp(q, tds, 0.001f, 1.0f);
	float[GLOBAL_SRATE] samples;
	tds.enqueueRead(q, samples[]).waitFor();
	writeWavFile("opencl_trochmod.wav", samples[], 10.0f);
}