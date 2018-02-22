import numpy
import scipy
import scipy.fftpack
import scipy.io.wavfile as wavfile
import matplotlib.pyplot as plt

mean = 256 / 2.0
std = mean / 3.0
dfreq = 8000
samples = numpy.random.normal(mean, std, size=dfreq * 5)
numpy.clip(samples, 0.0, 1.0)
samples = samples.astype(numpy.uint8)

# plt.plot(samples)
# plt.show()

wavfile.write('whitenoise3.wav', dfreq, samples)

fft = scipy.fftpack.fft(samples[0:dfreq])
fft[0] = 0

print(fft[0:10])

linfreq = scipy.fftpack.fftfreq(dfreq, 1.0 / dfreq)
plt.plot(linfreq, scipy.fftpack.fftshift(numpy.abs(fft.real)) / dfreq)
plt.show()