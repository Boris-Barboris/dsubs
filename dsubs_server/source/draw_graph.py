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

from itertools import cycle
cycol = cycle('bgrcmk')

i = 0
legendList = []
for entityDataFile in files:
    baseFileName = ntpath.basename(entityDataFile)
    data = genfromtxt(entityDataFile, delimiter=',', skip_header=1)
    # print(data)
    speeds = data[:, 0]
    noiselvls = data[:, 1]
    plt.plot(speeds, noiselvls, label=baseFileName)
    legendList.append(baseFileName)
    i = i + 1

plt.legend(legendList)
plt.show()