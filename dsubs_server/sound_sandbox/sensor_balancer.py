import copy
import numpy
import database as sdb
import simulator as sim
import matplotlib.pyplot as plt

ngenname = "Standard Screw"
#ngenname = "Eona hull"
sensorname = "Sphere"
splatpropname = "Standard Screw"
splathullname = "Eona hull"

noisegen = copy.deepcopy(sdb.g_noisegens[ngenname])
sensor = copy.deepcopy(sdb.g_sensors[sensorname])
sensor.parasites = [
    # host propulsor
    sim.ParasiticNoise(copy.deepcopy(sdb.g_noisegens[splatpropname]), 60.0, 2e-2),
    # host hull
    sim.ParasiticNoise(copy.deepcopy(sdb.g_noisegens[splathullname]), 25.0, 1)
]
sensor.parasites[0].gen.generationK = 0.0
sensor.parasites[1].gen.generationK = 0.0
sensor.resetBackground()


fig = plt.figure()
plt.suptitle(ngenname + " as perceived by " + sensorname)
ax = plt.subplot(221)
ax.set_title("Noise spectrum")
plt.semilogx(sim.FREQ_BINS, numpy.log10(noisegen.baseProfile) * 10.0, '-o')


ax = plt.subplot(222)
ax.set_title("Broadband SNR vs range and orientation")
ranges = numpy.arange(100.0, 20e3, 1e2)
snrs = numpy.empty([len(ranges)], float)
target = sim.TargetSignal(0.0, 0.0, 0.0, [noisegen])

for i, r in enumerate(ranges):
    target.range = r
    snrs[i] = sensor.getSNRdB(target)
plt.plot(ranges, snrs, label="from the back")

target.rotation = numpy.pi
for i, r in enumerate(ranges):
    target.range = r
    snrs[i] = sensor.getSNRdB(target)
plt.plot(ranges, snrs, label="from the front")
plt.axhline(y=0.0, color='r', linestyle=':')
plt.legend()


ax = plt.subplot(223)
ax.set_title("Narrowband SNR vs range")
target.rotation = 0
for binN in range(sensor.lowerBin, sensor.higherBin):
    for i, r in enumerate(ranges):
        target.range = r
        snrs[i] = sensor.getBinSNRdB(target, binN)
    f = sim.FREQ_BINS[binN]
    plt.plot(ranges, snrs, label=str(f) + " Hz")
plt.axhline(y=0.0, color='r', linestyle=':')
plt.legend()


ax = plt.subplot(224)
ax.set_title("Broadband SNR vs range vs host speed")
ranges = numpy.arange(100.0, 20e3, 1e2)
snrs = numpy.empty([len(ranges)], float)
target = sim.TargetSignal(0.0, 0.0, 0.0, [noisegen])

for parasGain in numpy.arange(0.0, 1.2, 0.2):
    # propulsor gain is squared
    sensor.parasites[0].gen.generationK = parasGain ** 5
    # hull gain is linear
    sensor.parasites[1].gen.generationK = parasGain ** 5
    # recalculate noise
    sensor.resetBackground()
    for i, r in enumerate(ranges):
        target.range = r
        snrs[i] = sensor.getSNRdB(target)
    plt.plot(ranges, snrs, label=str(int(100 * parasGain)) + "%")
plt.axhline(y=0.0, color='r', linestyle=':')
plt.legend()


fig.tight_layout()
plt.show()