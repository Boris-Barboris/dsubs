/*
Verification of correctness and liveness of various dsubs_server threads.
*/

#define CON_COUNT 3

// Simulator's rw lock
bit sim_wr_lock = 0;
byte sim_r_lock = 0;

// is player logged in (Player class created and put to PlayerCollection
bit player_created = 0;
// player collenciton mutex
bit playercoll_lock = 0;
// player's mutexes
bit player_locks[PLAYER_COUNT];
// is player's connection in simulator flow.
bit playercon_in_simflow[CON_COUNT];

bit subAlive = 0;

// Player.m_submarine
bit player_m_submarine = 0;
// Player.m_connection
byte active_con_idx = -1;


active proctype SimSchedulerThread()
{
    bit first_death_iter = 0;
    byte cached_active_con_idx = -1;
    do
    ::  // take simulator's writer lock
        d_step
        {
            sim_r_lock == 0 && sim_wr_lock == 0;
            sim_wr_lock = 1;
        }
        // with random chance kill the sub
        if
        ::  d_step
            {
                subAlive == 1;
                subAlive = 0;
            }
        ::  skip;
        fi
        // send update for each submarine whose captain is instance of Player class
        if
        ::  player_created && subAlive == 0 && player_m_submarine == 1;
            // sub was killed, set Player.m_submarine to null;
            player_m_submarine = 0;
            first_death_iter = 1;
        ::  else -> first_death_iter = 0;
        fi
        cached_active_con_idx = active_con_idx;
        if
        ::  player_created && first_death_iter && cached_active_con_idx >= 0 && subAlive == 0;
            // sub was killed, switch connection to not-in-sim-flow state
            playercon_in_simflow[cached_active_con_idx] = 0;
        ::  else -> skip;
        fi
        // release writer lock
        sim_wr_lock = 0;
    od
}


active [CON_COUNT] proctype PlayerConThread()
{

}