module dsubs_sound.water;

import dsubs_sound.common;


/// Get reference sea background noise band level
IntensityLevel seaNoiseIL(float freq)
{
	return IntensityLevel(75.0 - 7.0 * log2(freq / 20));
}