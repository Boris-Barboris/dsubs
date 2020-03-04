/*
Verification of correctness and liveness of various dsubs_server threads.
*/

#define CON_COUNT 3
#define UNSET 255

// Simulator's rw lock
bit sim_wr_lock = 0;
byte sim_r_lock = 0;

// is player logged in (Player class created and put to PlayerCollection
bit player_created = 0;
// player collenciton mutex
bit playercoll_lock = 0;
// player's recursive mutex
byte player_lock_depth;
pid player_lock_owner;
// is player's connection in simulator flow.
bit playercon_in_simflow[CON_COUNT];

bit subAlive = 0;

// Player.m_submarine
bit player_m_submarine = 0;
// Player.m_connection
byte active_con_idx = UNSET;


inline take_player_recursive(new_owner)
{
    d_step
    {
        player_lock_depth == 0 || player_lock_owner == new_owner;
        player_lock_depth++;
        player_lock_owner = new_owner;
    }
}

inline release_player_recursive()
{
    d_step
    {
        assert(player_lock_depth > 0);
        player_lock_depth--;
        if
        ::  player_lock_depth == 0 -> player_lock_owner = 0;
        ::  else -> skip;
        fi
    }
}


active proctype SimSchedulerThread()
{
    bit first_death_iter = 0;
    byte cached_active_con_idx = UNSET;
    do
    ::  // take simulator's writer lock
        d_step
        {
            sim_r_lock == 0 && sim_wr_lock == 0;
            sim_wr_lock = 1;
        }

        cached_active_con_idx = active_con_idx;

        // with random chance kill the sub
        if
        ::  d_step
            {
                subAlive == 1;
                subAlive = 0;
            }
        ::  skip;
        fi

        // safety property - active_con_idx does not change when simulator's write
        // lock is taken and the player has a submarine.
        assert(player_m_submarine == 0 || cached_active_con_idx == active_con_idx);

        // send update for each submarine whose captain is instance of Player class
        if
        ::  player_created && subAlive == 0 && player_m_submarine == 1;
            // sub was killed, set Player.m_submarine to null;
            player_m_submarine = 0;
            first_death_iter = 1;
        ::  else -> first_death_iter = 0;
        fi

        if
        ::  player_created && first_death_iter && cached_active_con_idx != UNSET &&
                subAlive == 0;
            // sub was killed, switch connection to not-in-sim-flow state
            playercon_in_simflow[cached_active_con_idx] = 0;
        ::  else -> skip;
        fi

        // release writer lock
        sim_wr_lock = 0;
    od
}


inline onConnectionClose()
{
    take_player_recursive(_pid);

    // take simulator's reader lock
    d_step
    {
        sim_wr_lock == 0;
        sim_r_lock++;
    }
    // here we modify submarine (disable hydrophones) and
    // some other ops of low importance.

    // now player has no active connection
    active_con_idx = UNSET;

    // release simulator's reader lock
    sim_r_lock--;

    release_player_recursive();
}


active [CON_COUNT] proctype PlayerConThread()
{
    // we assume that the connection auth always succeeds. There are no
    // important races during login check, and no locks are taken.
    player_created = 1;

    // synchronized(PlayerCollection)
    d_step
    {
        playercoll_lock == 0;
        playercoll_lock = 1;
    }

    if
    ::  // this may be the first time the player has logged in
        active_con_idx == UNSET;
        active_con_idx = _pid - 1;
    ::  // or there already is the connection there
        active_con_idx != UNSET;
        assert(active_con_idx != _pid - 1);

        // emplaceConnection synchronized(Player)
        take_player_recursive(_pid);

        // previous connection is closed
        onConnectionClose();
        // m_connection = con;
        active_con_idx = _pid - 1;

        // now we take sim read lock to enable submarine sensors and
        // verify that we are alive
        d_step
        {
            sim_wr_lock == 0;
            sim_r_lock++;
        }

        if
        ::  !subAlive;  // if sub is dead connection is closed
            sim_r_lock--;
            goto ON_CLOSE;
        ::  else -> skip;
        fi

        sim_r_lock--;

        // emplaceConnection synchronized(Player)
        release_player_recursive();
    fi

    // release synchronized(PlayerCollection)
    playercoll_lock = 0;

ON_CLOSE:
    onConnectionClose();
}


active proctype GlobalInvariants()
{
    atomic
    {
        assert(sim_r_lock >= 0);
        assert(player_lock_depth >= 0);
    }
}