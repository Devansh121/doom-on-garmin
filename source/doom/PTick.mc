// p_tick.c
//
// Archiving: SaveGame I/O.
// Thinker, Ticker.
//
// thinker_t lives in a fixed pool. A thinker's number is also the number
// of whatever it belongs to: a mobj's fields are PMobj.mobjs_*[n], and a
// sector special (door, plat, ...) keeps its fields in thinkers_data[n],
// an array indexed with that special's field constants. Slot 0 is
// thinkercap.
//
// Monkey C has no function pointers, so thinkers_function holds one of
// the TF_* numbers below and P_RunThinkers dispatches on it.

import Toybox.Lang;
import Toybox.System;

module PTick {

    // Pool size, set per level by P_InitThinkers: the map's things plus
    // room for what gets spawned during play (missiles, puffs, blood,
    // dropped items) and the sector specials.
    var maxthinkers as Number = 0;
    const EXTRATHINKERS = 112;

    // think_t values
    const TF_REMOVED = -1;      // (actionf_v)(-1), freed on the next run
    const TF_NULL = 0;          // NULL, e.g. plats and ceilings in stasis
    const TF_MOBJ = 1;          // P_MobjThinker
    const TF_VERTICALDOOR = 2;  // T_VerticalDoor
    const TF_MOVEFLOOR = 3;     // T_MoveFloor
    const TF_MOVECEILING = 4;   // T_MoveCeiling
    const TF_PLATRAISE = 5;     // T_PlatRaise
    const TF_LIGHTFLASH = 6;    // T_LightFlash
    const TF_STROBEFLASH = 7;   // T_StrobeFlash
    const TF_GLOW = 8;          // T_Glow
    const TF_FIRELIGHT = 9;     // T_FireFlicker

    var thinkers_prev as Array<Number> = [] as Array<Number>;
    var thinkers_next as Array<Number> = [] as Array<Number>;
    var thinkers_function as Array<Number> = [] as Array<Number>;
    var thinkers_data as Array<Array<Number>?> = [] as Array<Array<Number>?>;

    // Free slots, as a stack. Z_Malloc / Z_Free.
    var freelist as Array<Number> = [] as Array<Number>;
    var numfree as Number = 0;

    var leveltime as Number = 0;

    //
    // THINKERS
    // All thinkers should be allocated by Z_Malloc
    // so they can be operated on uniformly.
    // The actual structures will vary in size,
    // but the first element must be thinker_t.
    //

    //
    // P_InitThinkers
    //
    function P_InitThinkers(numthings as Number) as Void {
        maxthinkers = numthings + EXTRATHINKERS;
        thinkers_prev = new [maxthinkers] as Array<Number>;
        thinkers_next = new [maxthinkers] as Array<Number>;
        thinkers_function = new [maxthinkers] as Array<Number>;
        thinkers_data = new [maxthinkers] as Array<Array<Number>?>;
        freelist = new [maxthinkers] as Array<Number>;
        PMobj.P_InitMobjs(maxthinkers);

        thinkers_prev[0] = 0;
        thinkers_next[0] = 0;
        thinkers_function[0] = TF_NULL;
        numfree = 0;
        for (var i = maxthinkers - 1; i >= 1; i--) {
            freelist[numfree] = i;
            numfree++;
            thinkers_function[i] = TF_REMOVED;
            thinkers_data[i] = null;
        }
    }

    // Z_Malloc for a thinker: hands out a free slot.
    function P_AllocThinker() as Number {
        if (numfree == 0) {
            ISystem.I_Error("Z_Malloc: no free thinkers");
        }
        numfree--;
        return freelist[numfree];
    }

    //
    // P_AddThinker
    // Adds a new thinker at the end of the list.
    //
    function P_AddThinker(thinker as Number) as Void {
        thinkers_next[thinkers_prev[0]] = thinker;
        thinkers_next[thinker] = 0;
        thinkers_prev[thinker] = thinkers_prev[0];
        thinkers_prev[0] = thinker;
    }

    //
    // P_RemoveThinker
    // Deallocation is lazy -- it will not actually be freed
    // until its thinking turn comes up.
    //
    function P_RemoveThinker(thinker as Number) as Void {
        // FIXME: NOP.
        thinkers_function[thinker] = TF_REMOVED;
    }

    //
    // P_RunThinkers
    //
    // Resumable like the renderer: P_RunThinkersStep runs thinkers until
    // the budget (counted in thinkers) is used, and returns true once it
    // gets back to thinkercap.
    //
    var currentthinker as Number = 0;

    // budget left over when P_RunThinkersStep finishes the list
    var budgetleft as Number = 0;

    function P_RunThinkers() as Void {
        currentthinker = thinkers_next[0];
    }

    // Most thinkers are mobjs standing still (decorations, items, idle
    // monsters), and on the watch every call and every module variable
    // read costs tens of microseconds. For those P_MobjThinker only counts
    // the tics down, so P_RunIdleMobjs does that for a run of them in one
    // call, with the mobj arrays in locals, and P_MobjThinker is called
    // only for the rest. The order, the budget and what each thinker does
    // are as before.
    //
    // Every thinker's call chain starts in this frame and the VM stack
    // only has room for a couple of hundred slots, which is why the arrays
    // live in P_RunIdleMobjs, and why P_SetMobjState and P_MobjThinker are
    // called from here and not from there.
    var idlestatechange as Boolean = false;

    function P_RunThinkersStep(budget as Number) as Boolean {
        var next = thinkers_next;
        var funcs = thinkers_function;
        var t = currentthinker;
        var f;

        var deadline = RSegs.deadline;
        while (t != 0) {
            if (budget <= 0 || System.getTimer() >= deadline) {
                currentthinker = t;
                return false;
            }

            f = funcs[t];
            if (f == TF_MOBJ) {
                // idle mobjs from t on
                budgetleft = budget;
                f = P_RunIdleMobjs(t);
                budget = budgetleft;
                if (idlestatechange) {
                    // f counted down to 0: P_MobjThinker's
                    // you can cycle through multiple states in a tic
                    PMobj.P_SetMobjState(f, Info.states[PMobj.mobjs_state[f] * Info.ST_SIZE + Info.ST_NEXTSTATE]);
                    t = next[f];
                    continue;
                }
                if (f != t) {
                    // ran up to f, which is a thinker that still needs
                    // its turn (or 0, or the budget ran out)
                    t = f;
                    continue;
                }
                // t has to move or respawn
                budget--;
                PMobj.P_MobjThinker(t);
            } else if (f == TF_REMOVED) {
                budget--;
                // time to remove it
                f = next[t];
                thinkers_prev[f] = thinkers_prev[t];
                next[thinkers_prev[t]] = f;
                thinkers_data[t] = null;
                freelist[numfree] = t;
                numfree++;
                t = f;
                continue;
            } else {
                budget--;
                if (f != TF_NULL) {
                    P_Think(f, t);
                }
            }
            // read after the call, like the C code, so thinkers
            // added at the end of the list during it still run
            t = next[t];
        }
        currentthinker = 0;
        budgetleft = budget;
        return true;
    }

    // Runs P_MobjThinker for the mobjs from t on that don't move: no
    // momentum, not a skull in flight and on their floor, where it skips
    // both movement functions and only counts the tics down (or, for
    // tics == -1, does nothing unless a monster may respawn). Stops at the first thinker that isn't such a mobj
    // and returns it without running it (t itself if it's the first), or
    // at one whose tics just ran out, which it returns with
    // idlestatechange set so the caller does P_SetMobjState. Takes the
    // budget from budgetleft and leaves what's left there; returns 0 at
    // the end of the list.
    function P_RunIdleMobjs(t as Number) as Number {
        var next = thinkers_next;
        var funcs = thinkers_function;
        var momx = PMobj.mobjs_momx;
        var momy = PMobj.mobjs_momy;
        var momz = PMobj.mobjs_momz;
        var mflags = PMobj.mobjs_flags;
        var mz = PMobj.mobjs_z;
        var floorz = PMobj.mobjs_floorz;
        var tics = PMobj.mobjs_tics;
        var respawn = GGame.respawnmonsters;
        var budget = budgetleft;
        var tc;

        idlestatechange = false;
        while (t != 0 && budget > 0 && funcs[t] == TF_MOBJ) {
            if (momx[t] != 0
                || momy[t] != 0
                || (mflags[t] & PMobj.MF_SKULLFLY) != 0
                || mz[t] != floorz[t]
                || momz[t] != 0) {
                break;
            }

            tc = tics[t];
            if (tc == -1) {
                // P_MobjThinker's nightmare respawn check, which returns
                // straight away unless it's a monster and respawnmonsters
                // is on
                if (respawn && (mflags[t] & PMobj.MF_COUNTKILL) != 0) {
                    break;
                }
                budget--;
                t = next[t];
                continue;
            }
            budget--;

            // cycle through states,
            // calling action functions at transitions
            tc--;
            tics[t] = tc;
            if (tc == 0) {
                idlestatechange = true;
                break;
            }
            t = next[t];
        }
        budgetleft = budget;
        return t;
    }

    function P_Think(f as Number, t as Number) as Void {
        switch (f) {
            case TF_MOBJ:
                PMobj.P_MobjThinker(t);
                break;
            case TF_VERTICALDOOR:
                PDoors.T_VerticalDoor(t);
                break;
            case TF_MOVEFLOOR:
                PFloor.T_MoveFloor(t);
                break;
            case TF_MOVECEILING:
                PCeilng.T_MoveCeiling(t);
                break;
            case TF_PLATRAISE:
                PPlats.T_PlatRaise(t);
                break;
            case TF_LIGHTFLASH:
                PLights.T_LightFlash(t);
                break;
            case TF_STROBEFLASH:
                PLights.T_StrobeFlash(t);
                break;
            case TF_GLOW:
                PLights.T_Glow(t);
                break;
            case TF_FIRELIGHT:
                PLights.T_FireFlicker(t);
                break;
        }
    }

    //
    // P_Ticker
    //
    // Split in two so the thinker run can span several callbacks:
    // P_TickerStart, then P_TickerStep until it returns true.
    //
    var tickerstage as Number = 0;

    function P_TickerStart() as Void {
        // run the tic
        // (no pausing, menus or netgames on the watch)
        PUser.P_PlayerThink(0);
        P_RunThinkers();
        tickerstage = 1;
    }

    function P_TickerStep(budget as Number) as Boolean {
        budgetleft = budget;
        if (tickerstage == 1) {
            if (!P_RunThinkersStep(budget)) {
                budgetleft = 0;
                return false;
            }
            tickerstage = 2;
        }
        PSpec.P_UpdateSpecials();
        PMobj.P_RespawnSpecials();

        // for par times
        leveltime++;
        tickerstage = 0;
        return true;
    }
}
