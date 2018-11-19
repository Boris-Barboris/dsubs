module dsubs_sound.image;

import imageformats;

import dsubs_sound.common;
import dsubs_sound.spectrum;
import dsubs_sound.opencl;


void writeSpectrumTemplateImage(string filename, int binCount, int height)
{
	ubyte[] whiteData = new ubyte[binCount * height];
	whiteData[] = 255;
	write_png(filename, binCount, height, whiteData, 1);
}

void loadSpectrumFromImage(CommandQueue q, ref ILevelSpectrum dest,
	string filename, float bottomLevel = 80.0f, float topLevel = 160.0f)
{
	IFImage img = read_png(filename, 1);
	enforce(img.c == ColFmt.Y, "unexpected color format " ~ img.c.to!string);
	enforce(img.h > 0 && img.w > 0, "strange image dimensions");
	IntensityLevel[GLOBAL_SRATE / 2] bins;
	enforce(bins.length == img.w + 1, "invalid image width");

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
		bins[col] = IntensityLevel(topLevel - dy * fromTop);
	}
	dest = ILevelSpectrum(q, bins);
}

void loadSpectrumFromImageAndWarp(CommandQueue q, ref ILevelSpectrum dest,
	string filename, float noise,
	float bottomLevel = 80.0f, float topLevel = 160.0f)
{
	loadSpectrumFromImage(q, dest, filename, bottomLevel, topLevel);
	dest.addUniformNoise(q, noise);
}

unittest
{
	import std.array;
	import std.range;
	import std.algorithm;
	import std.stdio;
	import dsubs_sound.wav;

	auto ctx = s_clCtx;
	CommandQueue q = ctx.queue(0);

	writeSpectrumTemplateImage("2047bins.png", 2047, 1000);
	ILevelSpectrum ils;
	loadSpectrumFromImage(q, ils, "std_propeller.png");
	ils.patch(q, 0.0f, 0, 20);
	Tds tds = Tds(ctx);
	float[GLOBAL_SRATE] samples;
	ils.toTimeDomain(q, tds);
	tds.enqueueRead(q, samples[]).waitFor();
	float maxp = maxElement(samples[].map!(s => s.abs));
	writeln("loadSpectrumFromImageAndWarp maxp = ", maxp);
	writeWavFile("std_propeller_bb.wav", samples[], 0.8f / maxp, GLOBAL_SRATE);
}