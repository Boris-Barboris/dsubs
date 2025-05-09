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