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
    "Standard Screw": sim.PolynomialGenerator(
        numpy.array([40, 50, 80, 100, 150, 400, 300, 280,
        250, 210, 220, 200, 210, 150, 200, 330,
        500, 780, 2300, 3900, 4650, 2600, 2200, 1900,
        2100, 1200, 1500, 3100, 1000, 100, 300, 200]) * 5e3,
        0.2, 3.0),
    "Eona hull": sim.PolynomialGenerator(
        numpy.array([20, 25, 20, 24, 27, 45, 40, 15,
        18, 23, 28, 30, 27, 21, 15, 10,
        9, 8, 8, 8, 8, 7, 9, 20,
        25, 21, 17, 10, 8, 7, 4, 1]) * 1e3,
        0.0, 2.5, 1e-3),
}

g_sensors = {
    "Sphere": sim.NoiseReceiver(20, 32, 210, 105, []),
}