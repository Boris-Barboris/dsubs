srate = 128;
t = linspace(0.0, 2 * pi, srate);
data = 2.0 * sin(2 * pi * t + 0.07) + 0.5 * sin(5.76 * pi * t + 0.31);
x = complex(data);

function [Y] = naive_dft (X)
  N = length(X)
  W = @(k, n) X(n + 1) * exp(-2 * pi * i * (k - 1) * n / N)
  Bin = @(k) sum(arrayfun(@(n) W(k, n), [0:N-1]))
  Y = arrayfun(Bin, [1:N])
endfunction

function [x] = naive_idft (X)
  N = length(X)
  x = conj(naive_dft(conj(X))) ./ N
endfunction

# https://dsp.stackexchange.com/a/28712
function [x] = real_idft (X)
  N = length(X)
  Y = arrayfun(@(k) 0.5 * X(k + 1) * (1 + i * exp(2 * pi * i * k / N)) + \
    0.5 * conj(X(N/2 + 1 - k)) * (1 - i * exp(2 * pi * i * k / N)), [0:N/2-1])
  ComplexRes = conj(naive_dft(conj(Y))) ./ (N / 2)
  x = zeros(1, N)
  x(1:2:N) = real(ComplexRes)
  x(2:2:N) = imag(ComplexRes)
endfunction

dft_res = naive_dft(x);
idft_res = naive_idft(dft_res);
real_idft_res = real_idft(dft_res);
plot(t, data, t, dft_res, t, idft_res, t, real_idft_res);
legend ("source signal", "dft", "naive_idft", "real_idft");