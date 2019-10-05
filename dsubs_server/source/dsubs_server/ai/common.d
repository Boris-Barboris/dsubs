module dsubs_server.ai.common;


public import dsubs_server.ai.bt;


enum BOT_DIFFICULTY
{
	easy,
	medium,
	hard
}


/// Tick budget scaling for AI crew difficulty level.
int ticksPerDifficulty(BOT_DIFFICULTY diff)
{
	final switch (diff)
	{
		case BOT_DIFFICULTY.easy:
			return 100;
		case BOT_DIFFICULTY.medium:
			return 200;
		case BOT_DIFFICULTY.hard:
			return 250;
	}
}