import simulator as sim
import numpy
import matplotlib.pyplot as plt

# plot dissipation on on different frequencies
ilevels_1m_range = sim.toIntensityLevel(numpy.full([sim.FREQ_BIN_COUNT], 1e6))

ranges = [1e2, 1e3, 1e4] # 100m, 1km, 10km

# draw 1m intensity
fig = plt.figure()
ax = plt.subplot(211)
ax.set_title("Frequency dissipation")
plt.plot(sim.FREQ_BINS, ilevels_1m_range, label='1 meter (reference)')

for i in range(0, len(ranges)):
    ilevels_cur = numpy.empty([sim.FREQ_BIN_COUNT], float)
    for f in range(0, sim.FREQ_BIN_COUNT):
        ilevels_cur[f] = sim.getIntensityAtRange(f, ilevels_1m_range[f], ranges[i])
    plt.plot(sim.FREQ_BINS, ilevels_cur, label= str(ranges[i]) + ' meters')

plt.legend()

ax = plt.subplot(212)
ax.set_title("Range dissipation")
# plot dissipation on different ranges
ranges = numpy.arange(1e2, 1e4, 1e2)
ilevels = []
for r in ranges:
    ilevels.append(sim.getIntensityAtRange(10, ilevels_1m_range[10], r))

plt.plot(ranges, ilevels, label='on frequency ' + str(sim.FREQ_BINS[10]))
plt.legend()

fig.tight_layout()
plt.show()