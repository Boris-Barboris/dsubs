sf = 4096; sf2 = sf/2;
[b,a] = butter( 15, 600 / sf2 , "high");

clf
[h, w] = freqz (b, a, 512, sf);
freqz_plot (w, h);