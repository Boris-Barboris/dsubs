module dsubs_sound.wav;

import std.complex;
import std.conv: to;
import std.range;
import std.math;
import std.stdio;


// http://soundfile.sapp.org/doc/WaveFormat/
void writeWavFile(string filename, short[] samples, int srate = 4096)
{
	File f = File(filename, "wb");
	f.write("RIFF");
	f.rawWrite([0]);
	f.write("WAVE");
	f.write("fmt ");
	f.rawWrite([16]);
	f.rawWrite([short(1)]);	// PCM
	f.rawWrite([short(1)]);	// mono
	f.rawWrite([srate]);
	f.rawWrite([srate * 16 * 1 / 8]);
	f.rawWrite([short(16 * 1 / 8)]);
	f.rawWrite([short(16)]);
	f.write("data");
	f.rawWrite([(samples.length * short.sizeof).to!int]);
	f.rawWrite(samples);
	auto len = f.tell();
	f.seek(4);
	f.rawWrite([(len - 8).to!int]);
	f.flush();
	f.sync();
	f.close();
}

void writeWavFile(string filename, Complex!float[] samples, float norm, int srate = 4096)
{
	short[] ss;
	ss.length = samples.length;
	for (size_t i = 0; i < samples.length; i++)
		ss[i] = ((fmax(-1.0f, fmin(1.0f, samples[i].re / norm))) * short.max).to!short;
	writeWavFile(filename, ss, srate);
}

unittest
{
	import std.random;
	short[] samples = new short[4096 * 2];
	foreach (ref s; samples)
		s = uniform!short();
 	writeWavFile("noise.wav", samples);
}