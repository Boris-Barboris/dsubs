import numpy
import scipy
import wave
import scipy.fftpack
import scipy.io.wavfile as wavfile
import matplotlib.pyplot as plt
from scipy.signal import butter, lfilter


def butter_bandpass(lowcut, highcut, fs, order=5):
    nyq = 0.5 * fs
    low = lowcut / nyq
    high = highcut / nyq
    b, a = butter(order, [low, high], btype='band')
    return b, a


def butter_bandpass_filter(data, lowcut, highcut, fs, order=5):
    b, a = butter_bandpass(lowcut, highcut, fs, order=order)
    y = lfilter(b, a, data)
    return y

srate, data = wavfile.read('Modern Sonar Sounds and other Sounds of the Sea.wav')
print(srate)
print(len(data))

cut_data = data[44100 * 150 : 44100 * 151, 0]
plt.subplot(221)
plt.plot(cut_data)
# filter
cut_data = butter_bandpass_filter(cut_data, 1000, 3000, 44100, 5)

fft_res = scipy.fftpack.fft(cut_data)
fft_freqs = scipy.fftpack.fftfreq(len(cut_data), 1.0 / srate)

plt.subplot(222)
plt.plot(fft_freqs, 20 * numpy.log10(numpy.abs(fft_res) / len(cut_data)))
plt.subplot(223)
plt.plot(cut_data)
plt.show()
cut_data /= numpy.max(numpy.abs(cut_data[200:]), axis=0)
wavfile.write('filtered.wav', 44100, cut_data.astype(numpy.float32))