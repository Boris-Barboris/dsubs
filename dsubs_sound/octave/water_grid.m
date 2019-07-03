sf = 8192; sf2 = sf/2;

function res = waterRangeDissipationK(freq)
    f2 = (freq ./ 1e3) .^ 2;
    res11 = 0.11 .* f2 ./ (1.0 .+ f2);
    res12 = 44.0 .* f2 ./ (4100.0 .+ f2);
    res13 = 3e-4 .* f2;
    res = 2e-3 .* (res11 .+ res12 .+ res13);
end

freqSpace = linspace(1, sf2, sf2);

rangeSpace = linspace(0, 20000, 20);
dissipationK = 10 .^ ( - rangeSpace .* 4 .* waterRangeDissipationK(4000) ./ 20);

plot(rangeSpace, dissipationK);