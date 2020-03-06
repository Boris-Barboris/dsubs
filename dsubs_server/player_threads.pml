/*
Verification of correctness and liveness of various dsubs_server threads.
*/

#define CON_COUNT 3
#define UNSET 255

// Simulator's rw lock
bit sim_wr_lock = 0;
short sim_r_lock = 0;

// is player logged in (Player class created and put to PlayerCollection
bit player_created = 0;
// player collenciton mutex
bit playercoll_lock = 0;
// player's recursive mutex
short player_lock_depth;
pid player_lock_owner;
// is player's connection in simulator flow.
bit playercon_in_simflow[CON_COUNT];

#define NOT_SPAWNED 0
#define ALIVE 1
#define DEAD 2
byte subState = NOT_SPAWNED;

// Player.m_submarine is set or not
bit player_m_submarine = 0;
// Player.m_connection pointer
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
    byte cached_active_con_idx1 = UNSET;
    byte cached_active_con_idx2 = UNSET;
end:
    do
    ::  // take simulator's writer lock
        d_step
        {
            sim_r_lock == 0 && sim_wr_lock == 0;
            sim_wr_lock = 1;
        }

        // We don't allow arbitrary player's connection changes during simulator's run,
        // Only one connection per simulator update gets the update.
        cached_active_con_idx1 = active_con_idx;
        cached_active_con_idx2 = active_con_idx;

        // active sub's connection never changes throughout simulator's loop.
        if
        ::  subState != NOT_SPAWNED;
            assert(cached_active_con_idx1 == cached_active_con_idx2);
        ::  else -> skip;
        fi

        // with random chance kill the sub
        if
        ::  d_step
            {
                subState == ALIVE;
                subState = DEAD;
            }
        ::  skip;
        fi

        // send update for each submarine whose captain is instance of Player class
        if
        ::  player_created && subState == DEAD && player_m_submarine == 1;
            // sub was killed, set Player.m_submarine to null;
            player_m_submarine = 0;
        ::  else -> skip;
        fi

        if
        ::  player_created && cached_active_con_idx1 != UNSET && subState == DEAD;
            // sub was killed, switch connection to not-in-sim-flow state
            playercon_in_simflow[cached_active_con_idx1] = 0;
        ::  else -> skip;
        fi

        if
        ::  d_step
            {
                // allow respawn
                subState == DEAD;
                subState = NOT_SPAWNED;
            }
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

    // synchronized(PlayerCollection)
    d_step
    {
        playercoll_lock == 0;
        playercoll_lock = 1;
    }

    if
    ::  player_created == 0;
        // this may be the first time the player has logged in
        assert(active_con_idx == UNSET);
        active_con_idx = _pid - 1;
        // we assume that the connection auth always succeeds. There are no
        // important races during login check, and no locks are taken.
        player_created = 1;
    ::  active_con_idx != UNSET;
        assert(player_created == 1);
        // or there already is the connection there
        assert(active_con_idx != _pid - 1);

        // emplaceConnection synchronized(Player)
        take_player_recursive(_pid);

        // previous connection is closed
        onConnectionClose();

        // now we take sim read lock to enable submarine sensors and
        // verify that we are alive
        d_step
        {
            sim_wr_lock == 0;
            sim_r_lock++;
        }

        // m_connection = con;
        active_con_idx = _pid - 1;

        // Appears to be unreachable, because under sim lock
        // if
        // ::  subState == DEAD;  // if sub is dead connection is closed
        //     sim_r_lock--;
        //     playercoll_lock = 0;
        //     goto ON_CLOSE;
        // ::  else -> skip;
        // fi

        sim_r_lock--;

        // emplaceConnection synchronized(Player)
        release_player_recursive();
    fi

    // release synchronized(PlayerCollection)
    playercoll_lock = 0;

    // right next after the login user may disconnect
    if
    ::  goto ON_CLOSE;
    ::  skip;
    fi

    // next is the spawn or reconnect
    if
    ::  // spawn request
        take_player_recursive(_pid);
        // take simulator's reader lock
        d_step
        {
            sim_wr_lock == 0;
            sim_r_lock++;
        }
        // if there is a submarine we throw
        if
        ::  player_m_submarine == 1;
            sim_r_lock--;
            release_player_recursive();
            goto ON_CLOSE;
        ::  else -> skip;
        fi
        assert(subState == NOT_SPAWNED);
        // there is no submarine, we spawn
        subState = ALIVE;
        player_m_submarine = 1;
        sim_r_lock--;
        release_player_recursive();
        // set connection's simFlow flag
        playercon_in_simflow[_pid - 1] = 1;
    ::  // reconnect request
        // we only lock the simulator as there is no player state mutation
        // take simulator's reader lock
        d_step
        {
            sim_wr_lock == 0;
            sim_r_lock++;
        }
        if
        ::  player_m_submarine == 0;
            // throw if no submarine
            sim_r_lock--;
            goto ON_CLOSE;
        ::  player_m_submarine == 1 && subState == DEAD -> assert(false);
        ::  else -> skip;
        fi
        // invariant: we must not send reconnect state of the dead submarine
        assert(subState == ALIVE);
        sim_r_lock--;
        // set connection's simFlow flag
        playercon_in_simflow[_pid - 1] = 1;
    fi

    // we are now supposedly in sim flow

    // optional crash
    if
    ::  goto ON_CLOSE;
    ::  skip;
    fi

    // now actual ingame command arrives
    if
    ::  playercon_in_simflow[_pid - 1] == 0;
        // early exit because we are not in sim-flow already (died).
        goto ON_CLOSE;
    ::  else;
        // actual action
        // take simulator's reader lock
        d_step
        {
            sim_wr_lock == 0;
            sim_r_lock++;
        }
        if
        ::  player_m_submarine == 0;
            // throw if no submarine
            sim_r_lock--;
            goto ON_CLOSE;
        ::  subState == DEAD -> skip;  // early exit when sub is dead
        ::  else;
            // actual command issue
            // invariant: we must not update controllable state of a dead submarine
            // if we need so send a reply here, we use the same snapshotting technique.
            assert(subState == ALIVE);
        fi
        // release simulator's reader lock
        sim_r_lock--;
    fi

ON_CLOSE:
    onConnectionClose();
}


active proctype GlobalInvariants()
{
    atomic
    {
        assert(!(player_m_submarine == 1 && subState == NOT_SPAWNED));
        assert(sim_r_lock >= 0);
        assert(player_lock_depth >= 0);
    }
}