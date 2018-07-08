module dsubs_server.sound.wav;

import std.conv: to;
import std.range;
import std.random;
import std.stdio;


// http://soundfile.sapp.org/doc/WaveFormat/
void writeWavFile(string filename, short[] samples, int srate = 8000)
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

void writeWhiteNoise()
{
	short[] samples = new short[16000];
	foreach (ref s; samples)
		s = uniform!short();
	writeWavFile("noise.wav", samples);
}