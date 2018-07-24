module dsubs_sound.image;

import imageformats;

import dsubs_sound.common;
import dsubs_sound.spectrum;


void writeSpectrumTemplateImage(string filename, int binCount, int height)
{
	ubyte[] whiteData = new ubyte[binCount * height];
	whiteData[] = 255;
	write_png(filename, binCount, height, whiteData, 1);
}

IntensityLevelSpectrum loadSpectrumFromImage(
	string filename, float bottomLevel = 80.0f, float topLevel = 160.0f)
{
	IFImage img = read_png(filename, 1);
	enforce(img.c == ColFmt.Y, "unexpected color format " ~ img.c.to!string);
	enforce(img.h > 0 && img.w > 0, "strange image dimensions");
	IntensityLevelSpectrum res;
	res.bins.length = img.w;

	ubyte getPixel(int row, int column)
	{
		return img.pixels[img.w * row + column];
	}

	int getFirstNonwhite(int column)
	{
		int row = 0;
		while (row < img.h && getPixel(row, column) == 255)
			row++;
		return row;
	}

	float dy = (topLevel - bottomLevel) / img.h;
	for (int col = 0; col < img.w; col++)
	{
		int fromTop = getFirstNonwhite(col);
		res.bins[col] = topLevel - dy * fromTop;
	}

	return res;
}

unittest
{
	import std.array;
	import std.range;
	import std.algorithm;
	import std.stdio;
	import dsubs_sound.wav;
	import dsubs_sound.modulation;

	writeSpectrumTemplateImage("2047bins.png", 2047, 1000);
	auto ils = loadSpectrumFromImage("std_propeller.png");
	ils.addNumericNoise(0.5f);
	writeln("loaded spectrum from std_propeller.png: ", ils.bins[0..8]);
	writeln("std_propeller.png in linear scale: ", ils.toIntensity.bins[0..8]);
	Spectrum pspec;
	ils.genSpectrum(pspec);
	Fft fftCache = new Fft(4096);
	TimeDomainSignal tds;
	pspec.toTimeDomain(fftCache, tds);
	tds.samples = tds.samples.cycle.takeExactly(4096 * 5).array;
	AmplitudeModulator am = AmplitudeModulator(2.0f, 2.0f,
		[0.2f, 0.01f, 0.08f, 0.23f, 0.09f, 0.01f], 0.0f);
	am.modulate(tds);
	float maxp = tds.samples.map!(a => a.re).maxElement;
	writeln("std_propeller maxp: ", maxp);
	writeWavFile("std_propeller_bb.wav", tds.samples, 0.9f / maxp, tds.samplingRate);
}