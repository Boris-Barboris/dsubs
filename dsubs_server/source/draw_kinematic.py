#!/usr/bin/env python3

import glob
import sys
import re
import matplotlib.pyplot as plt
import numpy as np
import ntpath
from numpy import genfromtxt

testName = sys.argv[1]
filePattern = "test_data/" + testName + "*.csv"
print(filePattern)
files = glob.glob(filePattern)
print(files)
fileRegex = re.compile('.*_([\w\.0-9\(\)]+).csv')

from itertools import cycle
cycol = cycle('bgrcmk')

fig, ax = plt.subplots(1, 2, gridspec_kw={'width_ratios': [2, 1]})
ax[0].set_aspect('equal')
i = 0
for entityDataFile in files:
    baseFileName = ntpath.basename(entityDataFile)
    match = fileRegex.match(baseFileName)
    if match:
        data = genfromtxt(entityDataFile, delimiter=',', skip_header=1)
        # print(data)
        times = data[:, 0] / 1000000
        speeds = np.linalg.norm(data[:, 5:7], axis=1)
        pos_x = data[:, 1]
        pos_y = data[:, 2]
        dir_x = data[:, 3]
        dir_y = data[:, 4]
        vel_x = data[:, 5]
        vel_y = data[:, 6]
        groups = match.groups()
        entityName = groups[0]
        q = ax[0].quiver(pos_x, pos_y, vel_x, vel_y, scale_units='xy', scale=1,
            width=0.005)
        entColor = next(cycol)
        q = ax[0].quiver(pos_x, pos_y, dir_x, dir_y, scale_units='xy', scale=1,
            width=0.005, color=entColor)
        ax[0].quiverkey(q, X=0.15 + 0.2 * i, Y=0.9, U=15, label=entityName)
        # ax.quiverkey(q, X=0.25, Y=1.05, U=10, label=entityName + " velocity")
        ax[1].plot(times, speeds, entColor, label=entityName)
    i = i + 1

fig.tight_layout()
plt.show()
