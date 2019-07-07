module dsubs_sound.wav;

import std.algorithm.iteration;
import std.complex;
import std.conv: to;
import std.range;
import std.math;
import std.stdio;
import std.traits: Unqual;

import dsubs_sound.common: GLOBAL_SRATE, enforce;


// http://soundfile.sapp.org/doc/WaveFormat/
void writeWavFile(SR)(string filename, SR samples, int srate = GLOBAL_SRATE)
	if (isInputRange!SR && is(Unqual!(ElementType!SR) == short))
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

void writeWavFile(SR)(string filename, SR samples, float norm, int srate = GLOBAL_SRATE)
	if (isInputRange!SR && is(Unqual!(ElementType!SR) == float))
{
	writeWavFile(filename,
		samples.map!(s => ((fmax(-1.0f, fmin(1.0f, s * norm))) * short.max).to!short),
		srate);
}

/// load mono pcm16
void loadWavFile(string filename, out short[] samples, out int byteCount, out int srate)
{
	File f = File(filename, "rb");
	f.seek(4 + 4 + 4 + 4 + 4 + 2 + 2);
	int[] srateArr = f.rawRead(new int[1]);
	enforce(srateArr.length == 1, "unexpected eof in wav file");
	srate = srateArr[0];
	f.seek(40);
	int[] byteLen = f.rawRead(new int[1]);
	enforce(byteLen.length == 1, "unexpected eof in wav file");
	byteCount = byteLen[0];
	enforce(byteCount % 2 == 0, "not 16-bit PCM?");
	int sampleCount = (byteCount / short.sizeof).to!int;
	f.seek(44);
	samples = f.rawRead(new short[sampleCount]);
}