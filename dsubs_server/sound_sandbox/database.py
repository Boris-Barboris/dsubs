import numpy
import simulator as sim
import matplotlib.pyplot as plt

# Frequency bin middles:  [
# 22, 26, 32, 39, 48, 58, 71, 86,
# 105, 127, 154, 187, 228, 276, 335, 407,
# 495, 601, 730, 886, 1076, 1307, 1587, 1928,
# 2341, 2843, 3452, 4193, 5091, 6182, 7508, 9117]

g_noisegens = {
    # standard screw is 5-bladed screw of no particular speciality
    "Standard Screw": sim.NoiseGenerator(
        numpy.array([40, 50, 80, 100, 150, 400, 300, 280,
        250, 210, 220, 200, 210, 150, 200, 330,
        500, 780, 2300, 3900, 4650, 3600, 2400, 2000,
        1500, 1900, 4100, 3800, 3000, 5200, 3500, 2000]) * 5e12,
        0.2),
}

g_sensors = {
    "Sphere": sim.NoiseReceiver(20, 32, 210, 105),
}