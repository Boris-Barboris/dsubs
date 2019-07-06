sf = 8192; sf2 = sf/2;

function res = waterRangeDissipationK(freq)
    f2 = (freq ./ 1e3) .^ 2;
    res11 = 0.11 .* f2 ./ (1.0 .+ f2);
    res12 = 44.0 .* f2 ./ (4100.0 .+ f2);
    res13 = 3e-4 .* f2;
    res = 2e-3 .* (res11 .+ res12 .+ res13);
end

freqSpace = linspace(1, sf2, sf2);

rangeSpace = linspace(0, 40000, 40);
rangeSpace(1) = 100;
# dissipationK = 10 .^ ( - rangeSpace .* 4 .* waterRangeDissipationK(4000) ./ 20);
# plot(rangeSpace, dissipationK);

Bmat = [];

for i=1:length(rangeSpace)
    dissipationK = 10 .^ ( - rangeSpace(i) .* 4 .* waterRangeDissipationK(freqSpace) ./ 20);
    freqBands = zeros(1, sf);
    desiredResponse = zeros(1, sf);
    f = 0.0;
    dx = 1.0 / sf2; 
    for j = 1:sf2
      freqBands(j * 2 - 1) = f;
      f = f + dx;
      freqBands(j * 2) = f;
      desiredResponse(j * 2 - 1) = dissipationK(j);
      desiredResponse(j * 2) = dissipationK(j);
    end
    B = firls(20, freqBands, desiredResponse);
    Bmat = [Bmat; B.'];
endfor

csvwrite("water_filter_values.csv", Bmat);