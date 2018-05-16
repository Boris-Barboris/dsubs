import numpy
import scipy
import wave
import scipy.fftpack
import scipy.io.wavfile as wavfile
import matplotlib.pyplot as plt

topfreq = 6000
freq_range = numpy.linspace(1, topfreq, topfreq)
sea_db_freq = numpy.array([1.0, 10, 20, 100, 500, 1000, 10000])
sea_db_magn = numpy.array([110, 75, 70, 68, 60, 54, 38])

sea_interp = scipy.interpolate.interp1d(sea_db_freq, sea_db_magn)
sea_db_mean = sea_interp(freq_range)
# print(sea_db_mean[0:10])

sea_lin_mean = numpy.power(10.0, sea_db_mean / 20.0)
# print(sea_lin_mean[0:10])

def P2R(radius, angle):
    return radius * numpy.exp(angle * 1j)

def instantiate(lin_mean):
    radii = numpy.random.normal(lin_mean, lin_mean * 0.02, size=topfreq)
    radii[0:20] = 0.0
    angles = numpy.random.uniform(-3.14, 3.14, topfreq)
    print(angles[0:10])
    converter = numpy.vectorize(P2R)
    csignature = converter(radii, angles)
    print(csignature[19:24])
    # now let's make noise signature sparse
    for i in range(1, len(csignature)):
        if i > 1000:
            pass
            # if i % 2 != 0:
            #     csignature[i] = 0.0
            # else:
            #     pass
        else:
            csignature[i] = 0.0
            # csignature[i] /= 3.0
    fft_from_sig = numpy.concatenate(
        (numpy.array([0.0 + 1j * 0]), 0.5 * csignature,
            0.5 * numpy.flip(numpy.conjugate(csignature), 0)))
    print(fft_from_sig[0:5])
    # linfreq = scipy.fftpack.fftfreq(20001, 1.0)
    # print("linfreq " + str(linfreq))
    # plt.plot(linfreq, numpy.abs(fft_from_sig))
    # plt.show()
    return fft_from_sig


def get_timedomain(fft_res):
    ifft_res = scipy.fftpack.ifft(fft_res) * len(fft_res)
    # ifft_res /= 10.0 * numpy.max(ifft_res.real, axis=0)
    #scaled_timedomain = ifft_res.real * 0.5
    # numpy.clip(scaled_timedomain, -0.5, 0.5)
    # scaled_timedomain += 0.5
    # scaled_timedomain *= 255
    # ifft_res *= 32767.0
    # scaled_timedomain = ifft_res.astype(numpy.int16)
    return ifft_res

# time_range = numpy.linspace(0, 1.0, 20001)
# plt.plot(time_range, scaled_timedomain)
# plt.show()

def generate_1sec(i):
    print("Generating 1 second of sound ", i)
    return get_timedomain(instantiate(sea_lin_mean))

audio = numpy.concatenate([
    generate_1sec(0),
    generate_1sec(1),
    generate_1sec(2),
    generate_1sec(3),
    generate_1sec(4)
])

# let' try modulation

# print(numpy.sin(10.0 * numpy.linspace(0, 5, len(audio))) * 0.5 + 1.0)
audio = numpy.multiply(audio,
    numpy.sin(40.0 * numpy.linspace(0, 5, len(audio))) * 0.0 + 1.0)
audio /= 5.0 * numpy.max(audio.real, axis=0)
#audio *= 32767.0
#audio = audio.astype(numpy.int16)
audio *= 255.0 / 2.0
audio += 255.0 / 2.0
audio = audio.astype(numpy.int8)

wavfile.write('seanoise.wav', topfreq * 2, audio)

# now let's get fft of seanoise

srate, data = wavfile.read('seanoise.wav')
print(srate)

data = data.astype(float)
data /= 255
data -= 0.5
data *= 2

fft_res = scipy.fftpack.fft(data)
fft_freqs = scipy.fftpack.fftfreq((topfreq * 2 + 1) * 5, 1.0 / srate)

plt.plot(fft_freqs, numpy.abs(fft_res))
plt.show()