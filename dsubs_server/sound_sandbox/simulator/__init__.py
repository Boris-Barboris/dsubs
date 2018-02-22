import numpy
import math
import matplotlib.pyplot as plt


def toIntensityLevel(intensities):
    return numpy.log10(intensities) * 10.0

def toIntensity(ilevels):
    return numpy.power(10.0, ilevels / 10.0)

FREQ_BIN_BORDERS = numpy.round(numpy.geomspace(20, 10000, 33))
print("Frequency bin borders: ", FREQ_BIN_BORDERS)
FREQ_BIN_COUNT = 32
FREQ_BINS = []

for i in range(0, FREQ_BIN_COUNT):
    FREQ_BINS.append(int(0.5 * (FREQ_BIN_BORDERS[i + 1] + FREQ_BIN_BORDERS[i])))

print("Frequency bin middles: ", FREQ_BINS)

def freqBinWidth(bin):
    return FREQ_BIN_BORDERS[bin + 1] - FREQ_BIN_BORDERS[bin]

# let's calculate dissipation coefficients
g_freqDissipation = numpy.empty([FREQ_BIN_COUNT], float)
for i in range(0, FREQ_BIN_COUNT):
    f2 = (FREQ_BINS[i] * 1e-3) ** 2
    g_freqDissipation[i] = 2e-3 * (0.11 * f2 / (1 + f2) +
        44 * f2 / (4100 + f2) + 3e-4 * f2)

print("Dissipation koeffs: ", g_freqDissipation)

def getIntensityAtRange(freqBin, ilevel, range):
    return ilevel - toIntensityLevel(range * range) - g_freqDissipation[freqBin] * range

# let's deal with background noise
g_baseSeaNoiseDb = numpy.empty([FREQ_BIN_COUNT])
g_baseSeaNoise = numpy.empty([FREQ_BIN_COUNT])
for i in range(0, FREQ_BIN_COUNT):
    g_baseSeaNoiseDb[i] = 75.0 - 7.0 * numpy.log2(FREQ_BINS[i] / float(FREQ_BINS[0]))
    # account for bin width
    g_baseSeaNoiseDb[i] += toIntensityLevel(freqBinWidth(i))
    g_baseSeaNoise[i] = toIntensityLevel(g_baseSeaNoiseDb[i])

print("Background noise band intensities: ", g_baseSeaNoise)
print("Background noise band intensity levels: ", g_baseSeaNoiseDb)

def getBroadbandIntensity(ibands, startBin, endBin):
    res = 0.0
    for i in range(startBin, endBin):
        res += ibands[i]
    return res

def deg2rad(deg):
    return numpy.pi / 180.0 * deg


# analog of dsubs_server.sound.CosineDirectedNoise
class NoiseGenerator:
    def __init__(self, bandLevels, backNoiseK):
        self.generationK = 1.0
        self.backNoiseK = backNoiseK
        self.baseProfile = bandLevels

    def addNoisePowerTo(self, dir, output):
        k = 1.0 - abs(self.backNoiseK) - self.backNoiseK * math.cos(dir)
        for i in range(0, FREQ_BIN_COUNT):
            output[i] += self.generationK * k * self.baseProfile[i]


class TargetSignal:
    def __init__(self, range, course, rotation, noisegens):
        self.range = range
        self.course = course
        self.rotation = rotation
        self.noisegens = noisegens

    # get band intensity levels for receiver
    def getIntensity(self):
        result = numpy.full([FREQ_BIN_COUNT], 0.0)
        for gen in self.noisegens:
            gen.addNoisePowerTo(numpy.pi + self.course - self.rotation, result)
        for i in range(0, FREQ_BIN_COUNT):
            result[i] = toIntensity(getIntensityAtRange(i, toIntensityLevel(result[i]), self.range))
        return result


class ParasiticNoise:
    def __init__(self, gen, range, gain):
        self.gen = gen
        self.range = range
        self.gain = gain


# sound receiver
class NoiseReceiver:
    def __init__(self, lBin, hBin, span, antennaCount, parasites):
        self.lowerBin = lBin
        self.higherBin = hBin
        self.span = deg2rad(span)
        self.antennaCount = antennaCount
        self.parasites = parasites

    # clear buffer and apply bakcground noise
    def resetBackground(self):
        # get narrowband sea noise level
        self.iback = g_baseSeaNoise * (0.5 * self.span / numpy.pi / self.antennaCount)
        # calculate parasitic noise
        for parasite in self.parasites:
            iparasite = numpy.full([FREQ_BIN_COUNT], 0.0)
            parasite.gen.addNoisePowerTo(0, iparasite)
            iparasite *= parasite.gain / (parasite.range ** 2)
            self.iback += iparasite
        # calculate broadband noise
        self.ibackground = getBroadbandIntensity(self.iback,
            self.lowerBin, self.higherBin)


    # get broadband SNR for target
    def getSNR(self, target):
        ibands = target.getIntensity()
        broad = getBroadbandIntensity(ibands, self.lowerBin, self.higherBin)
        return broad / self.ibackground

    def getSNRdB(self, target):
        return toIntensityLevel(self.getSNR(target))

    # get narrowband SNR for target in frequency bin 'bin'
    def getBinSNR(self, target, bin):
        assert bin >= self.lowerBin
        assert bin < self.higherBin
        ibands = target.getIntensity()
        ibackbin = self.iback[bin]
        return ibands[bin] / ibackbin

    def getBinSNRdB(self, target, bin):
        return toIntensityLevel(self.getBinSNR(target, bin))