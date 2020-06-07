/*
Verification of correctness and liveness of playercon atomic replacement
and eviction, simulator start/stop and general referential integrity
of dsubs_server threading and entity model.
*/

#define CON_COUNT 3
#define SIM_COUNT 2
#define SUB_COUNT 3
#define UNSET 255


// Simulator:

// Simulator's rw lock
bit sim_wr_lock[SIM_COUNT];
short sim_r_lock[SIM_COUNT];

// simulator's playercon reference count
short sim_connectedPlayers[SIM_COUNT];

// End of Simulator

// simulator's state machine
#define SIM_INIT 0
#define SIM_RUNNING 1
#define SIM_TERMINATED 2

// scheduler's simulator collection
byte simStates[SIM_COUNT];
// index of the next simulator to allocate
byte allocSim = 0;
// simulator logical clocks
short simClocks[SIM_COUNT];


// Player:

// is player logged in (Player class created and put to PlayerCollection
bit player_created = 0;
// player collenciton mutex
bit playercoll_lock = 0;
// player's recursive mutex
short player_lock_depth;
pid player_lock_owner;

// End of Player


// submarine state machine
#define SUB_INIT 0
#define SUB_ALIVE 1
#define SUB_DEAD 2

// submarine states
byte subStates[SUB_COUNT];
// simulator pointers inside submarines
byte subSimPtrs[SUB_COUNT];
// index of the next submarine to allocate
byte allocSub = 0;

// Player.m_submarine pointer
byte player_m_submarine = UNSET;
// Player.m_connection pointer
byte active_con_idx = UNSET;
// Is player's connection in simulator flow.
// Server must not send simflow messages to connection that is not in sim flow.
bit playercon_in_simflow[CON_COUNT];
// player connection logical clocks. Used to track update sending.
short playerconClocks[SIM_COUNT];


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


inline sendTerminatedToPlayer(sim_idx, sub_idx)
{
    if
    ::  player_m_submarine != sub_idx;
        // Dangling submarine reference protection to prevent simulator
        // kicking out player that is no longer connected to it.
        goto skip_sendTerm;
    ::  else -> skip;
    fi

    // We assert that active sub's connection does not change
    // under sim's write lock. That way only one connection per
    // simulator update actually gets the update.
    assert(cached_active_con_idx1 == cached_active_con_idx2);

    player_m_submarine = UNSET;
    if
    ::  cached_active_con_idx1 != UNSET;
        playercon_in_simflow[cached_active_con_idx1] = 0;
        d_step
        {
            // connection's logical clock must not stutter, at most once delivery
            assert(playerconClocks[cached_active_con_idx1] < simClocks[sim_idx]);
            playerconClocks[cached_active_con_idx1] = simClocks[sim_idx];
        }
    ::  else -> skip;
    fi
skip_sendTerm:
}


inline sendUpdateToPlayer(sub_idx)
{
    if
    ::  player_m_submarine != sub_idx;
        goto skip_sendUpdate;
    ::  else -> skip;
    fi

    // We assert that active sub's connection does not change
    // under sim's write lock. That way only one connection per
    // simulator update actually gets the update.
    assert(cached_active_con_idx1 == cached_active_con_idx2);

    if
    ::  subStates[sub_idx] == SUB_DEAD;
        // s.simulator.decConnectedPlayers();
        sim_connectedPlayers[subSimPtrs[sub_idx]]--;
        // sub was killed, set Player.m_submarine to null;
        player_m_submarine = UNSET;
    ::  else -> skip;
    fi

    d_step
    {
        // connection's logical clock must not stutter, at most once delivery
        assert(playerconClocks[cached_active_con_idx1] < simClocks[sim_idx]);
        playerconClocks[cached_active_con_idx1] = simClocks[sim_idx];
    }

    if
    ::  cached_active_con_idx1 != UNSET && subStates[sub_idx] == SUB_DEAD &&
            playercon_in_simflow[cached_active_con_idx1];
        // sub was killed, switch connection to not-in-sim-flow state
        playercon_in_simflow[cached_active_con_idx1] = 0;
        goto skip_sendUpdate;
    ::  else -> skip;
    fi

    // Actual update generation and send is happening here, in place of this comment.
    // Verify that the connection is in simFlow.
    assert(playercon_in_simflow[cached_active_con_idx1] == 1);

skip_sendUpdate:
}


inline simulatorRunOnce(sim_idx)
{
    // take simulator's writer lock
    d_step
    {
        sim_r_lock[sim_idx] == 0 && sim_wr_lock[sim_idx] == 0;
        sim_wr_lock[sim_idx] = 1;
    }

    simClocks[sim_idx]++;

    // Used to check Player.m_connection immutability under sim's write lock.
    // Immutable only if the player is connected to this simulator.
    cached_active_con_idx1 = active_con_idx;
    cached_active_con_idx2 = active_con_idx;

    // random chance to terminate the simulator
    if
    ::  simStates[sim_idx] = SIM_TERMINATED;
        // send update for all the submarines of this simulator
	    for (i : 0 .. SUB_COUNT-1)
        {
            if
            ::  subStates[i] != SUB_INIT && subSimPtrs[i] == sim_idx;
                sendTerminatedToPlayer(sim_idx, i);
            ::  else -> skip;
            fi
        }
        goto release;
    ::  skip;
    fi

    // randomly kill the subs that belong to this sim
    for (i : 0 .. SUB_COUNT-1)
    {
        if
        ::  subStates[i] == SUB_ALIVE && subSimPtrs[i] == sim_idx;
            subStates[i] = DEAD;
        ::  skip;
        fi
    }

    // send update for each submarine whose captain is instance of Player class
    for (i : 0 .. SUB_COUNT-1)
    {
        if
        ::  subSimPtrs[i] == sim_idx;
            sendUpdateToPlayer(i);
        ::  else -> skip;
        fi
    }

release:
    // release writer lock
    sim_wr_lock[sim_idx] = 0;
}


active proctype SimSchedulerThread()
{
    byte cached_active_con_idx1 = UNSET;
    byte cached_active_con_idx2 = UNSET;
    byte i, j;
end:
    do
    // infinite loop that iterates over running simulators.
    ::  for (j : 0 .. SIM_COUNT-1)
        {
            if
            ::  simStates[j] == SIM_RUNNING;
                simulatorRunOnce(j);
            ::  else -> skip;
            fi:
        }
    od
}


// asynchronous Player.onConnectionClose that is called from one of connection's
// internal threads.
inline onConnectionClose(old_con_idx)
{
    take_player_recursive(_pid);

    cached_sub_idx = player_m_submarine;

    if
    ::  cached_sub_idx != UNSET;
        // take simulator's reader lock
        d_step
        {
            sim_wr_lock[subSimPtrs[cached_sub_idx]] == 0;
            sim_r_lock[subSimPtrs[cached_sub_idx]]++;
        }
    ::  else -> skip;
    fi

    // If this holds, cached_sub_idx is not actually needed.
    assert(cached_sub_idx == player_m_submarine);

    // here we modify submarine (disable hydrophones) and
    // some other ops of low importance.
    if
    ::  subStates[cached_sub_idx] == SUB_ALIVE;
        // sub.simulator.decConnectedPlayers();
        sim_connectedPlayers[subSimPtrs[cached_sub_idx]]--;
    ::  else -> skip;
    fi

    // unset player's connection
    if
    ::  old_con_idx == active_con_idx;
        active_con_idx = UNSET;
        // active_con_idx must be checked when we verify connection's process
    ::  else -> skip;
    fi

    if
    ::  cached_sub_idx != UNSET;
        // release simulator's reader lock
        sim_r_lock[subSimPtrs[cached_sub_idx]]--;
    ::  else -> skip;
    fi

    release_player_recursive();
}


active [CON_COUNT] proctype PlayerConThread()
{
    bit taken_sim_lock = 0;
    short cached_sub_idx = UNSET;
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
    ::  else;   // player exists
        assert(player_created == 1);
        // or there already is the connection there
        assert(active_con_idx != _pid - 1);

        // emplaceConnection synchronized(Player)
        take_player_recursive(_pid);

        // previous connection is closed
        if
        ::  active_con_idx != UNSET;
            onConnectionClose();
        ::  else -> skip;
        fi

        if
        ::  player_m_submarine == 1;
            // now we take sim read lock to enable submarine sensors and
            // verify that we are alive
            d_step
            {
                sim_wr_lock == 0;
                sim_r_lock++;
            }
            taken_sim_lock = 1;
        ::  else -> skip;
        fi

        // m_connection = con;
        active_con_idx = _pid - 1;

        if
        ::  taken_sim_lock == 1;
            sim_r_lock--;
        ::  else -> skip;
        fi

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
        assert(subStates == NOT_SPAWNED);
        // there is no submarine, we spawn
        subStates = ALIVE;
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
    byte i;
    atomic
    {
        assert(subStates[player_m_submarine] != SUB_INIT);
        assert(player_lock_depth >= 0);
        for (i : 0 .. SIM_COUNT-1)
        {
            // read lock count correctness
            assert(sim_r_lock[i] >= 0);
            // reference counting decrement correctness
            assert(sim_connectedPlayers[i] >= 0);
        }
    }
}