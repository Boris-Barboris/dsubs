import numpy
import math
import constants as cst


class Hydrophone:
    def __init__(self, fov, res, fmin, fmax):
        self.track = numpy.zeros(cst.MAX_FREQ * 2)
        self.fov = fov
        self.resolution = res
        self.fmin = fmin
        self.fmax = fmax
        self.matrix = numpy.zeros(res)
        self.volume_mult = 1.0 # human-controlled volume gain

    # calculate
    def _calcAvgSeaILForPixel(self):


# abstract sound source interface
class SoundSource:
    def __init__(self):
        self.size = 20.0 # affects the halo size on close distances

    # given relative bearing 'brng', return fraction of the
    # intensity that will be emitted in that direction.
    def _bearingGain(self, brng):
        return 1.0

    # add sound pressure time-sequence of unit length (1 second) to the 'output'
    # vector as perceived by directional hydrophone at range 'range' and
    # relative bearing 'brng'. hydrophone band is minf-maxf
    def addPressure(self, brng, range, output, minf, maxf):
        pass

    # return sound intensity level at range and bearing in specific band
    def getIlevel(self, brng, range, minf, maxf):
        return 0.0


# analog of dsubs_server.sound.CosineDirectedNoise
class NoiseGenerator:
    def __init__(self, bandLevels, backNoiseK):
        self.generationK = 1.0
        self.backNoiseK = backNoiseK
        self.baseProfile = bandLevels

    def gainFromGenK(self):
        return self.generationK

    def addNoisePowerTo(self, dir, output):
        k = 1.0 - abs(self.backNoiseK) - self.backNoiseK * math.cos(dir)
        for i in range(0, FREQ_BIN_COUNT):
            output[i] += self.gainFromGenK() * k * self.baseProfile[i]


# polynomial noise increase with generationK
class PolynomialGenerator(NoiseGenerator):
    def __init__(self, bandLevels, backNoiseK, exponent, zeroBias = 0.0):
        super().__init__(bandLevels, backNoiseK)
        self.exponent = exponent
        assert zeroBias >= 0.0
        assert zeroBias <= 1.0
        self.zeroBias = zeroBias

    def gainFromGenK(self):
        return self.zeroBias + (1.0 - self.zeroBias) * self.generationK ** self.exponent


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