sf = 8192; sf2 = sf/2;
b = fir1( 50, 250 / sf2 , "high");

clf
[h, w] = freqz (b, [1], 512, sf);
freqz_plot (w, h);
csvwrite("filter_values.csv", b)