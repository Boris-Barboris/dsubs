import numpy
import scipy
import wave
import scipy.fftpack
import scipy.io.wavfile as wavfile
import matplotlib.pyplot as plt

freq_range = numpy.linspace(1, 8000, 8000)
signature = numpy.random.normal(0.0, 0.33 * 100, size=8000)
# signature[0:40] = 0.0
csignature = numpy.add(signature, numpy.random.uniform(-3.14, 3.14, 8000) * 1j)

print(freq_range)
print(signature[39:43])
print(csignature[39:43])

fft_from_sig = numpy.concatenate(
    (numpy.array([0.0 + 1j * 0]), csignature, numpy.flip(csignature, 0)))
print(fft_from_sig[39:43])

ifft_from_sig = scipy.fftpack.ifft(fft_from_sig).real
print(ifft_from_sig)

time_range = numpy.linspace(0, 1.0, 16001)

plt.plot(time_range, ifft_from_sig.real)
plt.show()

wavfile.write('whitenoise_from_spec.wav', 16000, ifft_from_sig.real)