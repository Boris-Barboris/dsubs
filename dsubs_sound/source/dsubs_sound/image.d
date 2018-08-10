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
	res.bins.length = img.w + 2;
	assert(res.bins.length % 2 == 1);

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
		res.bins[col + 1] = topLevel - dy * fromTop;
	}
	// DC and nyquist always zero
	res.bins[0] = res.bins[$-1] = 0.0f;

	return res;
}

IntensityLevelSpectrum loadSpectrumFromImageAndWarp(string filename, float noise,
	float bottomLevel = 80.0f, float topLevel = 160.0f)
{
	IntensityLevelSpectrum res = loadSpectrumFromImage(filename, bottomLevel, topLevel);
	res.addNumericNoise(noise);
	return res;
}

unittest
{
	import std.array;
	import std.range;
	import std.algorithm;
	import std.stdio;
	import core.time;
	import dsubs_sound.wav;
	import dsubs_sound.modulation;
	import dsubs_sound.filter;

	writeSpectrumTemplateImage("2047bins.png", 2047, 1000);
	auto ils = loadSpectrumFromImage("std_propeller.png");
	ils.addNumericNoise(0.5f);
	Spectrum pspec;
	ils.bins[0..20] = IntensityLevel(0.0f);
	ils.genSpectrum(pspec);
	Fft fftCache = new Fft(2048);
	TimeDomainSignal tds;
	pspec.toTimeDomain(fftCache, tds);
	assert(tds.samplingRate == 4096);
	assert(tds.samples.length == 4096);
	tds.samples = tds.samples.cycle.takeExactly(4096 * 5).array;
	ThrachioidModulator am = new ThrachioidModulator(ThrachioidModulatorParams(
		[0.2f, 0.05f, 0.01f, 0.001f, 0.8f, 0.001f], 0.5, 0.7, -0.4));
	am.startFundFreq = am.endFundFreq = 2.0f;
	am.modulate(tds);
	TimeDomainSignal ftds = TimeDomainSignal(tds.samples.dup, tds.samplingRate);
	auto filtStart = MonoTime.currTime;
	highpass500.filter(tds.samples.cycled, ftds.samples);
	writeln("filtration took ", MonoTime.currTime() - filtStart);
	float maxp = ftds.samples.map!(a => a.re).maxElement;
	writeln("std_propeller maxp: ", maxp);
	writeWavFile("std_propeller_bb.wav", ftds.samples, 0.8f / maxp, ftds.samplingRate);
}