sf = 8192; sf2 = sf/2;

function res = waterRangeDissipationK(freq)
    f2 = (freq ./ 1e3) .^ 2;
    res11 = 0.11 .* f2 ./ (1.0 .+ f2);
    res12 = 44.0 .* f2 ./ (4100.0 .+ f2);
    res13 = 3e-4 .* f2;
    res = 2e-3 .* (res11 .+ res12 .+ res13);
end

freqSpace = linspace(1, sf2, sf2);
freqResponse = 10 .^ ( - 7000 .* 4 .* waterRangeDissipationK(freqSpace) ./ 20);

figure();
subplot(121);
plot(freqSpace, freqResponse);

freqBands = zeros(1, sf);
desiredResponse = zeros(1, sf);
f = 0.0;
dx = 1.0 / sf2;
for i = 1:sf2
  freqBands(i * 2 - 1) = f;
  f = f + dx;
  freqBands(i * 2) = f;
  desiredResponse(i * 2 - 1) = freqResponse(i);
  desiredResponse(i * 2) = freqResponse(i);
end

# fir2 is imprecise
# firls: https://cnx.org/contents/6x7LNQOp@7/Linear-Phase-Fir-Filter-Design-By-Least-Squares
[h, w] = freqz(firls(20,freqBands,desiredResponse));
subplot(122);
plot(freqBands, desiredResponse,';target response;', w ./pi, abs(h), ';filter response;');
