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

/*
Verification of correctness and liveness of PlayerConnection atomic replacement
and eviction for one Player instance, simulator start/stop and general
referential integrity of dsubs_server threading and entity model.

useful pan flags:
-QN set time-limit on execution of N minutes
-e  create trails for all errors
-r trailfilename  read and execute trail in file

to run:
spin -run -m250 -DMEMLIM=10000 -DCOLLAPSE -Q10 player_threads.pml
spin -run -bfs player_threads.pml
spin -run -bfspar -bit player_threads.pml
spin -run -dfspar player_threads.pml
to debug errors:
spin -l -g -p -replay player_threads.pml
*/

#define CON_COUNT 2
#define SIM_COUNT 2
#define SUB_COUNT 2
#define UNSET 255


// Simulator:

// simulator's state machine
#define SIM_INIT 0
#define SIM_RUNNING 1
#define SIM_TERMINATED 2

// Simulator's rw-mutexes, simMut field.
bit sim_wr_lock[SIM_COUNT];
short sim_r_lock[SIM_COUNT];

// simulator's playercon reference count, m_connectedPlayers field.
short sim_connectedPlayers[SIM_COUNT];

// scheduler's simulator collection. First (index 0) simulator is persistent.
byte simStates[SIM_COUNT];  // SIM_INIT etc...

// simulator logical clocks, that tick when simulation is running
short simClocks[SIM_COUNT];

// End of Simulator


// index of the next simulator to allocate. Abstracts away SimulatorScheduler fields.
byte allocSim = 1;


// Player:

// is player logged in (Player class created and put to PlayerCollection
bit player_created = 0;
// PlayerCollection.monitor instance mutex
bit playercoll_lock = 0;
// Player.monitor reenterant mutex
short player_lock_depth;
pid player_lock_owner;

// End of Player


// submarine state machine
#define SUB_INIT 0
#define SUB_ALIVE 1
#define SUB_DEAD 2

// submarine states. Subs do not revive.
byte subStates[SUB_COUNT];
// simulator pointers inside submarines. Killable.m_simulator field. Abstracts
// away submarineCollection membership as well.
byte subSimPtrs[SUB_COUNT];
// submarine-level reference counters. Submarine.m_conRefCount field.
short subConCounters[SUB_COUNT];
// index of the next submarine to allocate
byte allocSub = 0;
// mutex array of Submarine.monitor mutexes.
bit subLocks[SUB_COUNT];

// Player.m_submarine pointer
byte player_m_submarine = UNSET;
// Player.m_connection pointer
byte active_con_idx = UNSET;
// Is player's connection in simulator flow. +4 for the sake of _pid offset.
// PlayerConnection.m_simulatorFlow field.
bit playercon_in_simflow[CON_COUNT + 4];
// Connection has submarine pointer. PlayerConnection.m_simFlowSub field.
byte playerconSubFlowPtr[CON_COUNT + 4];
// synchronous shutdown+close flags.
// Equivalent to !ProtocolConnection.isOpen.
bit playercon_closed[CON_COUNT + 4];
// Player connection logical clocks. Used to track update messages and assert on
// duplication or causality errors. Not backed by actual code.
short playerconClocks[CON_COUNT + 4];
// number of closed connections
byte conClosedCounter;


// take player's reenterant lock once
inline take_player_recursive(new_owner)
{
    d_step
    {
        player_lock_depth == 0 || player_lock_owner == new_owner;
        player_lock_depth++;
        player_lock_owner = new_owner;
    }
}

// release player's reenterant lock once
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

// Simulator.sendTerminatingToPlayers loop's body for one player.
// Also Player.handleSimTerminating contents are represented here.
inline sendTerminatedToPlayer(sim_idx, sub_idx)
{
    if
    // Captain.unsetSubmarine
    ::  player_m_submarine != sub_idx;
        // Dangling submarine reference protection to prevent simulator
        // kicking out player that is no longer connected to it.
        goto skip_sendTerm;
    ::  else -> skip;
    fi

    // Player is connected to whis sim, so it must not change
    // connection pointer.
    assert(cached_active_con_idx1 == cached_active_con_idx2);

    if
    ::  cached_active_con_idx1 != UNSET;
        playercon_in_simflow[cached_active_con_idx1] = 0;
        if
        ::  playercon_closed[cached_active_con_idx1] == 0;  // if (con.isOpen)
            // connection's logical clock must not stutter
            assert(playerconClocks[cached_active_con_idx1] < simClocks[sim_idx]);
            // con.sendMessage(immutable SimulatorTerminatingRes());
            playerconClocks[cached_active_con_idx1] = 0;
        ::  else -> skip;
        fi
    ::  else -> skip;
    fi
    // Captain.unsetSubmarine
    player_m_submarine = UNSET;
skip_sendTerm:
}

// Player.sendUpdate
inline sendUpdateToPlayer(sub_idx)
{
    if
    ::  player_m_submarine != sub_idx;
        goto skip_sendUpdate;
    ::  else -> skip;
    fi

    // if there is no con, or con is closed, or
    // con.simulatorFlow is false, or con.simFlowSub is not our sub,
    // we skip the update.
    if
    ::  cached_active_con_idx1 == UNSET ||
            playercon_closed[cached_active_con_idx1] ||
            playercon_in_simflow[cached_active_con_idx1] == 0 ||
            playerconSubFlowPtr[cached_active_con_idx1] != sub_idx;
        goto unset_m_sub_if_dead;
    ::  else -> skip;
    fi

    // connection must never be changed under sim writer lock
    assert(cached_active_con_idx1 == cached_active_con_idx2);

    // Verify that the connection is in simFlow.
    assert(playercon_in_simflow[cached_active_con_idx1] == 1);

    // Connection's logical clock must not stutter, at most once delivery. Is also
    // cannot be lagging for more than 1 update behind because it is in-sync after
    // sending ReconnectStateRes.
    assert(playerconClocks[cached_active_con_idx1] == simClocks[subSimPtrs[sub_idx]] - 1);

    if
    ::  subStates[sub_idx] == SUB_DEAD; // sub is dead
        // sub was killed, switch connection to not-in-sim-flow state
        playercon_in_simflow[cached_active_con_idx1] = 0;
        // not that playerconSubFlowPtr is not unset here
        // reset ligical clock so we can reuse the connection object for next connection
        playerconClocks[cached_active_con_idx1] = 0;
        goto unset_m_sub_if_dead;
    ::  else -> skip;
    fi

    // Actual update generation and send is happening here, in place of this clock update
    playerconClocks[cached_active_con_idx1] = simClocks[subSimPtrs[sub_idx]];

    // Verify that submarine pointer in PlayerConnection is consistent and did not change
    assert(playerconSubFlowPtr[cached_active_con_idx1] == sub_idx);

unset_m_sub_if_dead:
    if
    ::  subStates[sub_idx] == SUB_DEAD;
        // sub was killed, set Player.m_submarine to null;
        player_m_submarine = UNSET;
    ::  else -> skip;
    fi

skip_sendUpdate:
}


// Submarine.incSubConRefCounter
inline incSubConCounter(sub_id)
{
    d_step
    {
        // take submarine lock
        subLocks[sub_id] == 0;
        subLocks[sub_id] = 1;
    }
    if
    ::  subConCounters[sub_id] == 0 && subSimPtrs[sub_id] != UNSET;
        d_step
        {
            sim_connectedPlayers[subSimPtrs[sub_id]]++;
            // sanity check
            assert(sim_connectedPlayers[subSimPtrs[sub_id]] <= SUB_COUNT);
        }
    ::  else -> skip;
    fi
    subConCounters[sub_id]++;   // m_conRefCount++
    subLocks[sub_id] = 0;   // release lock
}

// Submarine.decSubConRefCounter
inline decSubConCounter(sub_id)
{
    d_step
    {
        // take submarine lock
        subLocks[sub_id] == 0;
        subLocks[sub_id] = 1;
    }
    if
    ::  subConCounters[sub_id] == 1 && subStates[sub_id] == SUB_ALIVE &&
            subSimPtrs[sub_id] != UNSET;
        d_step
        {
            sim_connectedPlayers[subSimPtrs[sub_id]]--;
            assert(sim_connectedPlayers[subSimPtrs[sub_id]] >= 0);
        }
    ::  else -> skip;
    fi
    d_step
    {
        subConCounters[sub_id]--;   // m_conRefCount--;
        assert(subConCounters[sub_id] >= 0);
    }
    subLocks[sub_id] = 0;   // release lock
}


// Simulator.runOnce
inline simulatorRunOnce(sim_idx)
{
    // take simulator's writer lock
    d_step
    {
        sim_r_lock[sim_idx] == 0 && sim_wr_lock[sim_idx] == 0;
        sim_wr_lock[sim_idx] = 1;
    }

    // internal simulation state update, lots of stuff here
    simClocks[sim_idx]++;

    // Used to check Player.m_connection immutability under sim's write lock.
    // Immutable only if the player is connected to this simulator.
    cached_active_con_idx1 = active_con_idx;
    cached_active_con_idx2 = active_con_idx;

    // random chance to terminate non-persistent simulator
    if
    ::  sim_idx > 0;
        simStates[sim_idx] = SIM_TERMINATED;
        // send update for all the submarines of this simulator.
        // Sumulator.sendTerminatingToPlayers
        for (i : 0 .. SUB_COUNT-1)
        {
            if
            // subSimPtrs[i] == sim_idx check is not needed in D
            ::  subStates[i] == SUB_ALIVE && subSimPtrs[i] == sim_idx;
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
            // Submarine.onFirstKill called under lock
            if
            ::  subConCounters[i] > 0;
                // s.simulator.decConnectedPlayers() only called when sub has incremented
                // sim_connectedPlayers in the past
                d_step
                {
                    // death makes simulator dangling
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
    // These two pointers are checking atomicity of certain operations.
    // If they are assigned from shared value under lock and differ
    // after the assignment, the lock that was held was not respected and
    // the connection pointer has changed. That would mean that
    // parts of player update go to different connections and they recieve
    // partial state update, which must never happen. E.g under simulator's
    // writer lock, Players that have a sub in the simulator must never alter
    // their connection pointer while simulator writer lock is held.
    byte cached_active_con_idx1 = UNSET;
    byte cached_active_con_idx2 = UNSET;
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
        decSubConCounter(playerconSubFlowPtr[old_con_idx]);
        playerconSubFlowPtr[old_con_idx] = UNSET;
        playercon_in_simflow[old_con_idx] = 0;
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

    // second block of locks for current player's sub sim.
    // player_m_submarine may have changed during this time.
    cached_sub_idx = player_m_submarine;

    if
    ::  cached_sub_idx != UNSET;
        // take simulator's reader lock, since next step is
        // to change active_con_idx and it cannot be changed
        // under writer's lock.
        d_step
        {
            sim_wr_lock[subSimPtrs[cached_sub_idx]] == 0;
            sim_r_lock[subSimPtrs[cached_sub_idx]]++;
        }
    ::  else -> skip;
    fi

    // unset player's connection
    if
    ::  old_con_idx == active_con_idx;
        active_con_idx = UNSET;
        // active_con_idx must be checked when we verify connection's process.
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


// Thread that waits until all connections are closed and
// verifies some postconditions.
active proctype PostConditionVerifier()
{
    byte i;
    d_step
    {
        conClosedCounter == CON_COUNT;
        // ensure that simulator reference counts are zero when all connections
        // have closed
        for (i : 0 .. SIM_COUNT-1)
        {
            assert(simStates[i] != SIM_RUNNING || sim_connectedPlayers[i] == 0);
        }
    }
}


/// Thread that
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

    // right after the login user may randomly disconnect
    if
    ::  goto ON_CLOSE;
    ::  skip;
    fi

    // Stage2: spawn or reconnect, entering simflow

BEFORE_SIMFLOW:

    // next is the spawn or reconnect
    if
    ::  // spawn sub +-sim request
        take_player_recursive(_pid);

        cached_sub_idx = player_m_submarine;
        // if there already is a submarine we throw an error
        if
        ::  cached_sub_idx != UNSET;
            release_player_recursive();
            goto ON_CLOSE;
        ::  else -> skip;
        fi

        // we create a simulator or choose persistent 0 sim
        if
        ::  d_step
            {
                allocSim < SIM_COUNT;
                cached_sim_idx = allocSim;
                allocSim++;
            }
        ::  cached_sim_idx = 0; // persistent simulator
        ::  // out of SIM_COUNT
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
        ::  else;   // out of SUB_COUNT.
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
        // here con.sendMessage(getReconnectState()); is called, so we initialize
        // the clock
        playerconClocks[_pid] = simClocks[cached_sim_idx];

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
            // this is unneeded because when sub dies, player_m_submarine
            // is unset under sim's writer lock
            // if
            // ::  subStates[cached_sub_idx] == SUB_DEAD;
            //     sim_r_lock[cached_sim_idx]--;
            //     release_player_recursive();
            //     goto ON_CLOSE;
            // ::  else -> skip;
            // fi

            // reconnect state is generated and sent in place of this comment
            assert(subStates[cached_sub_idx] == SUB_ALIVE);
            // simulator is alive
            assert(simStates[cached_sim_idx] == SIM_RUNNING);
            incSubConCounter(cached_sub_idx);
            playerconSubFlowPtr[_pid] = cached_sub_idx;
            playercon_in_simflow[_pid] = 1;
            // initialize the clock
            playerconClocks[_pid] = simClocks[cached_sim_idx];
            // release locks
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
    ::  // let's say it's some kind of write, for example targetCouse update
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
        // guard against sim termination (player_m_submarine can change)
        if
        ::  cached_sub_idx != player_m_submarine;
            sim_r_lock[subSimPtrs[cached_sub_idx]]--;
            goto ON_CLOSE;
        ::  else -> skip;
        fi
        assert(cached_sub_idx == player_m_submarine);
        // actual command is issued to submarine here.
        // invariant: we must not update controllable state of a dead submarine
        // if we need so send a reply here, we use the same snapshotting technique.
        // this holds, so there is no need for s.dead check under sim.rearer lock in
        // player class methods.
        assert(subStates[cached_sub_idx] == SUB_ALIVE);
        // another invariant, simulator must be new or running
        assert(simStates[subSimPtrs[cached_sub_idx]] < SIM_TERMINATED);
        // release simulator's reader lock
        sim_r_lock[subSimPtrs[cached_sub_idx]]--;
    ::  skip;
    fi

    // check closed
    if
    ::  playercon_closed[_pid] == 1;
        goto ON_CLOSE;
    ::  else -> skip;
    fi

    if
    ::  playercon_in_simflow[_pid] == 0;
        // when no longer in simflow, client may request to connect to another
        // scenario or spawn new one again, without re-authorizing.
        goto BEFORE_SIMFLOW;
    ::  skip;
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
    conClosedCounter++;
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
        // there cannot be more than one alive submarine in all running sims, because
        // there is only one player. Subs are not killed when sim is terminated, so
        // SIM_RUNNING state check is mandatory.
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