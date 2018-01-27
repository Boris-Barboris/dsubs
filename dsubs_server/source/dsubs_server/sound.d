module dsubs_server.sound;

import dsubs_server.rng;


struct NoiseDiscrete
{
	float freq;
	float width;
	float strength;
}


interface NoiseSource
{
	const(NoiseDiscrete)[] getNoise();
}


final class NoiseEmitter
{

}