import numpy
import database as sdb
import simulator as sim
import matplotlib.pyplot as plt

ngenname = "Standard Screw"
sensorname = "Sphere"

noisegen = sdb.g_noisegens[ngenname]
sensor = sdb.g_sensors[sensorname]


fig = plt.figure()
plt.suptitle(ngenname + " as perceived by " + sensorname)
ax = plt.subplot(221)
ax.set_title("Noise spectrum")
plt.semilogx(sim.FREQ_BINS, noisegen.baseProfile, '-o')


ax = plt.subplot(222)
ax.set_title("Broadband SNR vs range")
ranges = numpy.arange(100.0, 20e3, 1e2)
snrs = numpy.empty([len(ranges)], float)
target = sim.TargetSignal(0.0, 0.0, 0.0, [noisegen])

for i, r in enumerate(ranges):
    target.range = r
    sensor.resetToBackground()
    snrs[i] = sensor.getSNRdB(target)
plt.plot(ranges, snrs, label="propeller from the back")

target.rotation = numpy.pi
for i, r in enumerate(ranges):
    target.range = r
    snrs[i] = sensor.getSNRdB(target)
plt.plot(ranges, snrs, label="propeller from the front")
plt.axhline(y=0.0, color='r', linestyle=':')
plt.legend()


ax = plt.subplot(223)
binN = 20
ax.set_title("Narrowband SNR vs range for bin " + str(sim.FREQ_BINS[binN]) + " Hz")
target.rotation = 0
for i, r in enumerate(ranges):
    target.range = r
    snrs[i] = sensor.getBinSNRdB(target, binN)
plt.plot(ranges, snrs, label="propeller from the back")
plt.axhline(y=0.0, color='r', linestyle=':')
plt.legend()


fig.tight_layout()
plt.show()