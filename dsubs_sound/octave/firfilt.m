sf = 4096; sf2 = sf/2;
b = fir1( 20, 550 / sf2 , "high");

clf
[h, w] = freqz (b, [1], 512, sf);
freqz_plot (w, h);