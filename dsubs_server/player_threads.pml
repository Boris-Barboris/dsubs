/*
Verification of correctness and liveness of playercon atomic replacement
and eviction, simulator start/stop and general referential integrity
of dsubs_server threading and entity model.

to run:
spin -run -m200 player_threads.pml
spin -run -bfs player_threads.pml
spin -run -bfspar -bit player_threads.pml
spin -run -dfspar player_threads.pml
to debug errors:
spin -l -p -replay player_threads.pml
*/

#define CON_COUNT 2
#define SIM_COUNT 1
#define SUB_COUNT 2
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

// scheduler's simulator collection. First simulator is persistent.
byte simStates[SIM_COUNT];
// index of the next simulator to allocate
byte allocSim = 1;
// simulator logical clocks
short simClocks[SIM_COUNT];


// Player:

// is player logged in (Player class created and put to PlayerCollection
bit player_created = 0;
// PlayerCollection.monitor mutex
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
// submarine-level reference counters
short subConCounters[SUB_COUNT];
// index of the next submarine to allocate
byte allocSub = 0;
// mutex array
bit subLocks[SUB_COUNT];

// Player.m_submarine pointer
byte player_m_submarine = UNSET;
// Player.m_connection pointer
byte active_con_idx = UNSET;
// Is player's connection in simulator flow.
bit playercon_in_simflow[CON_COUNT + 4];
// Connection has submarine pointer
byte playerconSubFlowPtr[CON_COUNT + 4];
// synchronous shutdown+close flags
bit playercon_closed[CON_COUNT + 4];
// player connection logical clocks. Used to track update sending.
short playerconClocks[CON_COUNT + 4];
// queue of connections that are reported as closed
chan conIdxAsClosedQueue = [CON_COUNT - 1] of { byte };


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

    if
    ::  subStates[sub_idx] == SUB_DEAD;
        // sub was killed, set Player.m_submarine to null;
        player_m_submarine = UNSET;
    ::  else -> skip;
    fi

    // if con.simulatorFlow is false we skip the update send
    if
    ::  cached_active_con_idx1 == UNSET ||
            playerconSubFlowPtr[cached_active_con_idx1] != sub_idx;
        goto skip_sendUpdate;
    ::  else -> skip;
    fi

    d_step
    {
        // connection's logical clock must not stutter, at most once delivery
        assert(playerconClocks[cached_active_con_idx1] < simClocks[subSimPtrs[sub_idx]]);
        playerconClocks[cached_active_con_idx1] = simClocks[subSimPtrs[sub_idx]];
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
    // Submarine pointer is consistent
    assert(playerconSubFlowPtr[cached_active_con_idx1] == sub_idx);

skip_sendUpdate:
}


inline incSubConCounter(sub_id)
{
    d_step
    {
        subLocks[sub_id] == 0;
        subLocks[sub_id] = 1;
    }
    if
    ::  subConCounters[sub_id] == 0;
        sim_connectedPlayers[subSimPtrs[sub_id]]++;
    ::  else -> skip;
    fi
    subConCounters[sub_id]++;
    subLocks[sub_id] = 0;
}


inline decSubConCounter(sub_id)
{
    d_step
    {
        subLocks[sub_id] == 0;
        subLocks[sub_id] = 1;
    }
    if
    ::  subConCounters[sub_id] == 1 && subStates[sub_id] == SUB_ALIVE;
        d_step
        {
            sim_connectedPlayers[subSimPtrs[sub_id]]--;
            assert(sim_connectedPlayers[subSimPtrs[sub_id]] >= 0);
        }
    ::  else -> skip;
    fi
    d_step
    {
        subConCounters[sub_id]--;
        assert(subConCounters[sub_id] >= 0);
    }
    subLocks[sub_id] = 0;
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

    // random chance to terminate non-persistent simulator
    if
    ::  sim_idx > 0;
        simStates[sim_idx] = SIM_TERMINATED;
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
        ::  d_step
            {
                // take sub lock
                subStates[i] == SUB_ALIVE && subSimPtrs[i] == sim_idx && subLocks[i] == 0;
                subLocks[i] = 1;
            }
            subStates[i] = SUB_DEAD;
            if
            ::  subConCounters[i] > 0;
                // s.simulator.decConnectedPlayers() only called when sub has incremented
                // sim_connectedPlayers in the past
                d_step
                {
                    sim_connectedPlayers[sim_idx]--;
                    assert(sim_connectedPlayers[sim_idx] >= 0);
                }
            ::  else -> skip;
            fi
            subLocks[i] = 0;
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


proctype SimSchedulerThread()
{
    byte cached_active_con_idx1 = UNSET;
    byte i, j;
end:
    do
    // infinite loop that iterates over running simulators.
    ::
        for (j : 0 .. SIM_COUNT-1)
        {
            if
            ::  simStates[j] == SIM_RUNNING;
                simulatorRunOnce(j);
            ::  else -> skip;
            fi
        }
    od
}


// asynchronous Player.onConnectionClose that is called from one of connection's
// internal threads.
inline onConnectionClose(old_con_idx)
{
    take_player_recursive(_pid);

    cached_sub_idx = playerconSubFlowPtr[old_con_idx];

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
    // assert(cached_sub_idx == player_m_submarine);

    if
    ::  cached_sub_idx != UNSET;
        decSubConCounter(playerconSubFlowPtr[old_con_idx]);
        playerconSubFlowPtr[old_con_idx] = UNSET;
        playercon_in_simflow[old_con_idx] = 0;
    ::  else -> skip;
    fi

    // unset player's connection
    if
    ::  old_con_idx == active_con_idx;
        active_con_idx = UNSET;
        // active_con_idx must be checked when we verify connection's process.
    ::  else -> skip;
    fi

    // here we modify submarine (disable hydrophones) and
    // some other ops of low importance.

    if
    ::  cached_sub_idx != UNSET;
        // release simulator's reader lock
        sim_r_lock[subSimPtrs[cached_sub_idx]]--;
    ::  else -> skip;
    fi

    release_player_recursive();
}


// Thread that calls onConnectionClose asynchronously.
active proctype PlayerConCloser()
{
    byte oldConIdx;
    byte cached_sub_idx;
    short counter;
    byte i;
    do
    ::  d_step
        {
            conIdxAsClosedQueue?oldConIdx;
            counter++
        }
        if
        ::  d_step
            {
                counter == CON_COUNT;
                // ensure that simulator reference counts are zero when all connections
                // have closed
                for (i : 0 .. SIM_COUNT-1)
                {
                    assert(simStates[i] != SIM_RUNNING || sim_connectedPlayers[i] == 0);
                }
            }
            goto end;
        ::  else -> skip;
        fi
    od
end:
}


proctype PlayerConThread()
{
    bit taken_sim_lock = 0;
    byte cached_sub_idx = UNSET;
    byte cached_sim_idx = UNSET;
    // synchronized(PlayerCollection)
    d_step
    {
        playercoll_lock == 0;
        playercoll_lock = 1;
    }

    if

    // Stage1a: initial player creation

    ::  player_created == 0;
        // Player is logged in
        assert(active_con_idx == UNSET);
        active_con_idx = _pid;
        // we assume that the connection auth always succeeds. There are no
        // interesting races during login check, and no locks are taken.
        player_created = 1;

    // Stage1b: player's connection emplacement

    ::  else;   // player exists
        assert(player_created == 1);
        assert(active_con_idx != _pid);

        // emplaceConnection synchronized(Player)
        take_player_recursive(_pid);

        // previous connection is closed
        if
        ::  active_con_idx != UNSET;
            // closeConnection();
            atomic
            {
                if
                ::  playercon_closed[active_con_idx] == 0;
                    playercon_closed[active_con_idx] = 1;
                ::  else -> skip;
                fi
            }
        ::  else -> skip;
        fi

        cached_sub_idx = player_m_submarine;

        if
        ::  cached_sub_idx != UNSET;
            // now we take sim read lock verify that we are alive
            d_step
            {
                sim_wr_lock[subSimPtrs[cached_sub_idx]] == 0;
                sim_r_lock[subSimPtrs[cached_sub_idx]]++;
            }
            taken_sim_lock = 1;

            // if (sub.dead || sub.simulator.finished) block
            if
            ::  subStates[cached_sub_idx] == SUB_DEAD ||
                    simStates[subSimPtrs[cached_sub_idx]] == SIM_TERMINATED;
                player_m_submarine = UNSET;
            ::  else -> skip;
            fi
        ::  else -> skip;
        fi

        // m_connection = con;
        active_con_idx = _pid;

        if
        ::  taken_sim_lock == 1;
            sim_r_lock[subSimPtrs[cached_sub_idx]]--;
        ::  else -> skip;
        fi

        // emplaceConnection synchronized(Player) end
        release_player_recursive();
    fi

    // release synchronized(PlayerCollection)
    playercoll_lock = 0;


    // Stage2: spawn or reconnect

    // right next after the login user may disconnect
    if
    ::  goto ON_CLOSE;
    ::  skip;
    fi

    // next is the spawn or reconnect
    if
    ::  // spawn sub +-sim request
        take_player_recursive(_pid);

        cached_sub_idx = player_m_submarine;
        // if there is a submarine we throw
        if
        ::  cached_sub_idx != UNSET;
            release_player_recursive();
            goto ON_CLOSE;
        ::  else -> skip;
        fi

        // we create a simulator
        if
        ::  d_step
            {
                allocSim < SIM_COUNT;
                cached_sim_idx = allocSim;
                allocSim++;
            }
        ::  cached_sim_idx = 0; // persistent simulator
        ::  // out of memory
            release_player_recursive();
            goto ON_CLOSE;
        fi

        // take simulator's reader lock
        d_step
        {
            sim_wr_lock[cached_sim_idx] == 0;
            sim_r_lock[cached_sim_idx]++;
        }

        // create submarine
        if
        ::  d_step
            {
                allocSub < SUB_COUNT;
                cached_sub_idx = allocSub;
                subStates[cached_sub_idx] = SUB_ALIVE;
                allocSub++;
            }
        ::  else;   // out of memory
            sim_r_lock[cached_sim_idx]--;
            release_player_recursive();
            goto ON_CLOSE;
        fi

        // bind sub to simulator...
        // next two lines - order is important
        subSimPtrs[cached_sub_idx] = cached_sim_idx;
        player_m_submarine = cached_sub_idx;
        // ... and schedule simulator
        simStates[cached_sim_idx] = SIM_RUNNING;    // fits persistent case
        incSubConCounter(cached_sub_idx);
        playerconSubFlowPtr[_pid] = cached_sub_idx;
        playercon_in_simflow[_pid] = 1;

        sim_r_lock[cached_sim_idx]--;
        release_player_recursive();

    ::  // reconnect request
        take_player_recursive(_pid);
        cached_sub_idx = player_m_submarine;
        if
        ::  cached_sub_idx == UNSET;
            // throw if no submarine
            release_player_recursive();
            goto ON_CLOSE;
        ::  else;
            cached_sim_idx = subSimPtrs[cached_sub_idx];
            // take simulator's reader lock
            d_step
            {
                sim_wr_lock[cached_sim_idx] == 0;
                sim_r_lock[cached_sim_idx]++;
            }
            // check wether player_m_submarine changed during read lock taking.
            if
            ::  cached_sub_idx != player_m_submarine;
                sim_r_lock[cached_sim_idx]--;
                release_player_recursive();
                goto ON_CLOSE;
            ::  else -> skip;
            fi
            assert(cached_sub_idx == player_m_submarine);
            // throw if submarine is dead
            if
            ::  subStates[cached_sub_idx] == SUB_DEAD;
                sim_r_lock[cached_sim_idx]--;
                release_player_recursive();
                goto ON_CLOSE;
            ::  else -> skip;
            fi

            // reconnect state is generated and sent in place of this comment
            assert(subStates[cached_sub_idx] == SUB_ALIVE);
            incSubConCounter(cached_sub_idx);
            playerconSubFlowPtr[_pid] = cached_sub_idx;
            playercon_in_simflow[_pid] = 1;
            sim_r_lock[cached_sim_idx]--;
            release_player_recursive();
        fi
    fi

    // we are now accepting sim flow commands

    // optional connection crash
    if
    ::  goto ON_CLOSE;
    ::  skip;
    fi

    // check closed
    if
    ::  playercon_closed[_pid] == 1;
        goto ON_CLOSE;
    ::  else -> skip;
    fi

    // now actual ingame command arrives, it is either sim abandon or some write
    if
    ::  // let's say it's a write
        cached_sub_idx = player_m_submarine;
        if
        ::  cached_sub_idx == UNSET;
            // ignore command when there is no sub
            goto ON_CLOSE;
        ::  else -> skip;
        fi
        // take simulator's reader lock
        d_step
        {
            sim_wr_lock[subSimPtrs[cached_sub_idx]] == 0;
            sim_r_lock[subSimPtrs[cached_sub_idx]]++;
        }
        // guard against sim termination
        if
        ::  cached_sub_idx != player_m_submarine;
            sim_r_lock[subSimPtrs[cached_sub_idx]]--;
            goto ON_CLOSE;
        ::  else -> skip;
        fi
        assert(cached_sub_idx == player_m_submarine);
        if
        ::  subStates[cached_sub_idx] == SUB_DEAD;
            // ignore command when the sub is dead
            sim_r_lock[subSimPtrs[cached_sub_idx]]--;
            goto ON_CLOSE;
        ::  else;
            // actual command issue
            // invariant: we must not update controllable state of a dead submarine
            // if we need so send a reply here, we use the same snapshotting technique.
            assert(subStates[cached_sub_idx] == SUB_ALIVE);
        fi
        // release simulator's reader lock
        sim_r_lock[subSimPtrs[cached_sub_idx]]--;

    ::  // let's say it's abandon
        skip;   // TODO
    fi

ON_CLOSE:
    // closeConnection();
    if
    ::  d_step
        {
            playercon_closed[_pid] == 0;
            playercon_closed[_pid] = 1;
        }
    ::  else -> skip;
    fi
    onConnectionClose(_pid);
    conIdxAsClosedQueue!_pid;
}


active proctype GlobalInvariants()
{
    byte i;
    short aliveCounter;
    atomic
    {
        if
        ::  player_m_submarine != UNSET;
            assert(subStates[player_m_submarine] != SUB_INIT);
        ::  else -> skip;
        fi
        assert(player_lock_depth >= 0);
        for (i : 0 .. SIM_COUNT-1)
        {
            // read lock count correctness
            assert(sim_r_lock[i] >= 0);
            // reference counting decrement correctness
            assert(sim_connectedPlayers[i] >= 0);
        }
        // there cannot be more than one alive submarine in all running sims
        for (i : 0 .. SUB_COUNT-1)
        {
            if
            ::  subStates[i] == SUB_ALIVE && subSimPtrs[i] != UNSET &&
                    simStates[subSimPtrs[i]] == SIM_RUNNING;
                aliveCounter++;
            ::  else -> skip;
            fi
        }
        assert(aliveCounter <= 1);
    }
}


init
{
    byte i;
    atomic
    {
        simStates[0] = SIM_RUNNING; // initialize persistent simulator
        for (i : 0 .. SUB_COUNT-1)
        {
            subSimPtrs[i] = UNSET;
        }
        run SimSchedulerThread();
        for (i : 0 .. CON_COUNT-1+4)
        {
            playerconSubFlowPtr[i] = UNSET;
        }
        for (i : 0 .. CON_COUNT-1)
        {
            run PlayerConThread();
        }
    }
}