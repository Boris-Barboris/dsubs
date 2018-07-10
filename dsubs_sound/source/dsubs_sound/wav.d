module dsubs_sound.wav;

import std.algorithm.iteration;
import std.complex;
import std.conv: to;
import std.range;
import std.math;
import std.stdio;


// http://soundfile.sapp.org/doc/WaveFormat/
void writeWavFile(SR)(string filename, SR samples, int srate = 4096)
	if (isInputRange!SR && is(ElementType!SR == short))
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
	f.rawWrite([0]);
	int sampleCount = 0;
	foreach(s; samples)
	{
		f.rawWrite([s]);
		sampleCount++;
	}
	auto len = f.tell();
	f.seek(4);
	f.rawWrite([(len - 8).to!int]);
	f.seek(40);
	f.rawWrite([(sampleCount * short.sizeof).to!int]);
}

void writeWavFile(CSR)(string filename, CSR samples, float norm, int srate = 4096)
	if (isInputRange!CSR && is(ElementType!CSR == Complex!float))
{
	writeWavFile(filename,
		samples.map!(s => ((fmax(-1.0f, fmin(1.0f, s.re * norm))) * short.max).to!short),
		srate);
}