import numpy
import math

# transform verctor of intensities to intensity level
def toIntensityLevel(intensities):
    return numpy.log10(intensities) * 10.0

# vice versa
def toIntensity(ilevels):
    return numpy.power(10.0, ilevels / 10.0)

def _waterRangeDissipationK(freq):
    f2 = (freq * 1e-3) ** 2
    res = 2e-3 * (0.11 * f2 / (1 + f2) +
        44 * f2 / (4100 + f2) + 3e-4 * f2)
    return res

# get reduced frequency bin intensity level at range
def getIntensityAtRange(freq, ilevel, range):
    return ilevel - toIntensityLevel(range * range) - _waterRangeDissipationK(freqBin) * range

# omnidirectional narrowband sea noise intensity
def seaNoiseIntensity(freq):
    return 75.0 - 7.0 * numpy.log2(freq / 20.0)

def deg2rad(deg):
    return numpy.pi / 180.0 * deg

# min and maximum frequencies that dsubs acoustic system will handle
MIN_FREQ = 20
MAX_FREQ = 10000