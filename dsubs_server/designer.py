import numpy as np
import matplotlib.pyplot as plt

shape1 = [
    0.0, 35.0,
    -1.5, 34.8,
    -3, 34,
    -3.5, 33.0,
    -4, 32.2,
    -4.7, 30.0,
    -5.0, 28.0,
    -5.0, -18.0,
    -4.5, -23.0,
    -3.0, -28.0,
    -2.0, -31.0,
    0.0, -35.0
]

shape2 = [
    0.0, 15.0,
    -1.0, 14.7,
    -1.7, 14.0,
    -2.0, 13.0,
    -2.0, 4.0,
    -1.7, 2.0,
    -1.0, 0.5,
    0.0, -1.0
]

def plotSymShape(pointSeq):
    for i in range(0, int(len(pointSeq) / 2) - 1):
        plt.plot(
            [pointSeq[i * 2], pointSeq[i * 2 + 2]],
            [pointSeq[i * 2 + 1], pointSeq[i * 2 + 3]],
            'b-')
    for i in range(0, int(len(pointSeq) / 2) - 1):
        plt.plot(
            [-pointSeq[i * 2], -pointSeq[i * 2 + 2]],
            [pointSeq[i * 2 + 1], pointSeq[i * 2 + 3]],
            'b-')

plotSymShape(shape1)
plotSymShape(shape2)

plt.axis([-40, 40, -40, 40])

plt.show()