/*
DSubs
Copyright (C) 2017-2025 Baranin Alexander

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
module dsubs_sound.water;

import dsubs_sound.spectrum;
import dsubs_sound.common;


/// Speed of sound
enum float SOUND_SPD = 1498;

/// Get reference sea background noise band level
IntensityLevel seaNoiseIL(float freq)
{
	assert(freq > 0.0f);
	return IntensityLevel(70.0 - 6.0 * log2(freq / 20));
}


/// Reference propagation loss coefficient
private float waterRangeDissipationK(float freq)
{
	// DMD bugs on windows produce NaNs here, that's
	// why res11-res13 are needed
	float f2 = pow(freq / 1e3, 2);
	float res11 = 0.11 * f2 / (1 + f2);
	float res12 = 44 * f2 / (4100 + f2);
	float res13 = 3e-4 * f2;
	float res = 2e-3 * (res11 + res12 + res13);
	return res;
}

// frequency of 1Hz is on offset 0
package __gshared immutable(float)[] wrdk;

void initializeWrdk()
{
	float[] prep_wrdk;
	prep_wrdk.length = GLOBAL_SRATE / 2;
	for (int i = 1; i <= GLOBAL_SRATE / 2; i++)
		prep_wrdk[i - 1] = waterRangeDissipationK(i);
	wrdk = cast(immutable(float)[]) prep_wrdk;
}

/// Scale intensity level of a band as if it is received underwater at range
IntensityLevel getILatRange(int freq, IntensityLevel il, float range, float dissMod = 1.0f)
{
	assert(freq > 0 && freq <= GLOBAL_SRATE / 2);
	return IntensityLevel(il - toDb(range * range) - wrdk[freq - 1] * range * dissMod);
}

/// Same but with toDb(range * range) precalculated
IntensityLevel getILatRange2(int freq, IntensityLevel il, float range, float rangeDb, float dissMod = 1.0f)
{
	assert(freq > 0 && freq <= GLOBAL_SRATE / 2);
	return IntensityLevel(il - rangeDb - wrdk[freq - 1] * range * dissMod);
}

/*

unittest
{
	IntensityLevel il = IntensityLevel(100.0f);
	auto ilDamped = getILatRange(100, il, 10000.0f);
	assert(!isNaN(ilDamped.val));
	assert(!isInfinity(ilDamped.val));
	assert(ilDamped < 100.0f);
}

*/

/// band intensity level of flow noise
IntensityLevel flowNoise(int freq, float kts)
{
	assert(freq > 0);
	assert(kts >= 0.0f, "kts is " ~ kts.to!string);
	dB res = 68.0f;
	// 18 db per knot doubling
	res += fabs(kts) * 1.8f;
	// 9db per octave fall
	res -= 9.0f * log2(fmax(freq, 100.0f) / 1000.0f);
	return IntensityLevel(res);
}

/// halo half-angle of point sound source at specified range.
float pointHaloAngle(float range)
{
	return dgr2rad(0.5f);
}