// st_stuff.c / st_stuff.h
//
// DESCRIPTION:
//	Status bar code.
//	Does the face/direction indicator animatin.
//	Does palette indicators as well (red pain/berserk, bright pickup)
//
// ST_Responder and the cheats aren't here (no keyboard on the watch), nor
// is the netgame face background or the chat state. The status bar is
// drawn into a 320x32 BufferedBitmap that the view scales onto the
// screen; ST_doPaletteStuff only picks the palette number, which the view
// shows as a translucent tint (see HudLumps.tints).

import Toybox.Graphics;
import Toybox.Lang;

(:extendedCode)
module StStuff {

    //
    // STATUS BAR DATA
    //

    // Palette indices.
    // For damage/bonus red-/gold-shifts
    const STARTREDPALS = 1;
    const STARTBONUSPALS = 9;
    const NUMREDPALS = 8;
    const NUMBONUSPALS = 4;
    // Radiation suit, green shift.
    const RADIATIONPAL = 13;

    // N/256*100% probability
    //  that the normal face state will change
    const ST_FACEPROBABILITY = 96;

    // Location of status bar
    const ST_X = 0;
    const ST_X2 = 104;

    const ST_FX = 143;
    const ST_FY = 169;

    // Number of status faces.
    const ST_NUMPAINFACES = 5;
    const ST_NUMSTRAIGHTFACES = 3;
    const ST_NUMTURNFACES = 2;
    const ST_NUMSPECIALFACES = 3;

    const ST_FACESTRIDE = ST_NUMSTRAIGHTFACES + ST_NUMTURNFACES + ST_NUMSPECIALFACES;

    const ST_NUMEXTRAFACES = 2;

    const ST_NUMFACES = ST_FACESTRIDE * ST_NUMPAINFACES + ST_NUMEXTRAFACES;

    const ST_TURNOFFSET = ST_NUMSTRAIGHTFACES;
    const ST_OUCHOFFSET = ST_TURNOFFSET + ST_NUMTURNFACES;
    const ST_EVILGRINOFFSET = ST_OUCHOFFSET + 1;
    const ST_RAMPAGEOFFSET = ST_EVILGRINOFFSET + 1;
    const ST_GODFACE = ST_NUMPAINFACES * ST_FACESTRIDE;
    const ST_DEADFACE = ST_GODFACE + 1;

    const ST_FACESX = 143;
    const ST_FACESY = 168;

    const ST_EVILGRINCOUNT = 2 * DoomDef.TICRATE;
    const ST_STRAIGHTFACECOUNT = DoomDef.TICRATE / 2;
    const ST_TURNCOUNT = 1 * DoomDef.TICRATE;
    const ST_OUCHCOUNT = 1 * DoomDef.TICRATE;
    const ST_RAMPAGEDELAY = 2 * DoomDef.TICRATE;

    const ST_MUCHPAIN = 20;

    // Location and size of statistics,
    //  justified according to widget type.
    // Problem is, within which space? STbar? Screen?
    // Note: this could be read in by a lump.
    //       Problem is, is the stuff rendered
    //       into a buffer,
    //       or into the frame buffer?

    // AMMO number pos.
    const ST_AMMOWIDTH = 3;
    const ST_AMMOX = 44;
    const ST_AMMOY = 171;

    // HEALTH number pos.
    const ST_HEALTHWIDTH = 3;
    const ST_HEALTHX = 90;
    const ST_HEALTHY = 171;

    // Weapon pos.
    const ST_ARMSX = 111;
    const ST_ARMSY = 172;
    const ST_ARMSBGX = 104;
    const ST_ARMSBGY = 168;
    const ST_ARMSXSPACE = 12;
    const ST_ARMSYSPACE = 10;

    // Frags pos.
    const ST_FRAGSX = 138;
    const ST_FRAGSY = 171;
    const ST_FRAGSWIDTH = 2;

    // ARMOR number pos.
    const ST_ARMORWIDTH = 3;
    const ST_ARMORX = 221;
    const ST_ARMORY = 171;

    // Key icon positions.
    const ST_KEY0WIDTH = 8;
    const ST_KEY0HEIGHT = 5;
    const ST_KEY0X = 239;
    const ST_KEY0Y = 171;
    const ST_KEY1WIDTH = ST_KEY0WIDTH;
    const ST_KEY1X = 239;
    const ST_KEY1Y = 181;
    const ST_KEY2WIDTH = ST_KEY0WIDTH;
    const ST_KEY2X = 239;
    const ST_KEY2Y = 191;

    // Ammunition counter.
    const ST_AMMO0WIDTH = 3;
    const ST_AMMO0HEIGHT = 6;
    const ST_AMMO0X = 288;
    const ST_AMMO0Y = 173;
    const ST_AMMO1WIDTH = ST_AMMO0WIDTH;
    const ST_AMMO1X = 288;
    const ST_AMMO1Y = 179;
    const ST_AMMO2WIDTH = ST_AMMO0WIDTH;
    const ST_AMMO2X = 288;
    const ST_AMMO2Y = 191;
    const ST_AMMO3WIDTH = ST_AMMO0WIDTH;
    const ST_AMMO3X = 288;
    const ST_AMMO3Y = 185;

    // Indicate maximum ammunition.
    // Only needed because backpack exists.
    const ST_MAXAMMO0WIDTH = 3;
    const ST_MAXAMMO0HEIGHT = 5;
    const ST_MAXAMMO0X = 314;
    const ST_MAXAMMO0Y = 173;
    const ST_MAXAMMO1WIDTH = ST_MAXAMMO0WIDTH;
    const ST_MAXAMMO1X = 314;
    const ST_MAXAMMO1Y = 179;
    const ST_MAXAMMO2WIDTH = ST_MAXAMMO0WIDTH;
    const ST_MAXAMMO2X = 314;
    const ST_MAXAMMO2Y = 191;
    const ST_MAXAMMO3WIDTH = ST_MAXAMMO0WIDTH;
    const ST_MAXAMMO3X = 314;
    const ST_MAXAMMO3Y = 185;

    // main player in game (a player number)
    var plyr as Number = 0;

    // ST_Start() has just been called
    var st_firsttime as Boolean = false;

    // used to execute ST_Init() only once
    var veryfirsttime as Number = 1;

    // used for timing
    var st_clock as Number = 0;

    // used for making messages go away
    var st_msgcounter as Number = 0;

    // whether left-side main status bar is active
    var st_statusbaron as Boolean = false;

    // whether status bar chat is active
    var st_chat as Boolean = false;

    // value of st_chat before message popped up
    var st_oldchat as Boolean = false;

    // !deathmatch
    var st_notdeathmatch as Boolean = false;

    // !deathmatch && st_statusbaron
    var st_armson as Boolean = false;

    // !deathmatch
    var st_fragson as Boolean = false;

    // The patches are HudLumps numbers, see StLib; ST_loadGraphics
    // fills these lists.

    // 0-9, tall numbers
    var tallnum as Array<Number> = [] as Array<Number>;

    // 0-9, short, yellow (,different!) numbers
    var shortnum as Array<Number> = [] as Array<Number>;

    // 3 key-cards, 3 skulls
    var keys as Array<Number> = [] as Array<Number>;

    // face status patches
    var faces as Array<Number> = [] as Array<Number>;

    // weapon ownership patches, arms[6][2]
    var arms as Array<Array<Number> > = [] as Array<Array<Number> >;

    // ready-weapon widget
    var w_ready as st_number_t = new st_number_t();
    // what w_ready.num points at: an ammo type, -1 for largeammo
    var w_ready_ammo as Number = -1;

    // in deathmatch only, summary of frags stats
    var w_frags as st_number_t = new st_number_t();

    // health widget
    var w_health as st_percent_t = new st_percent_t();

    // arms background
    var w_armsbg as st_binicon_t = new st_binicon_t();

    // weapon ownership widgets
    var w_arms as Array<st_multicon_t> = [] as Array<st_multicon_t>;

    // face status widget
    var w_faces as st_multicon_t = new st_multicon_t();

    // keycard widgets
    var w_keyboxes as Array<st_multicon_t> = [] as Array<st_multicon_t>;

    // armor widget
    var w_armor as st_percent_t = new st_percent_t();

    // ammo widgets
    var w_ammo as Array<st_number_t> = [] as Array<st_number_t>;

    // max ammo widgets
    var w_maxammo as Array<st_number_t> = [] as Array<st_number_t>;

    // number of frags so far in deathmatch
    var st_fragscount as Number = 0;

    // used to use appopriately pained face
    var st_oldhealth as Number = -1;

    // used for evil grin
    var oldweaponsowned as Array<Number> = new [DoomDef.NUMWEAPONS] as Array<Number>;

    // count until face changes
    var st_facecount as Number = 0;

    // current face index, used by w_faces
    var st_faceindex as Number = 0;

    // holds key-type for each key box on bar
    var keyboxes as Array<Number> = [-1, -1, -1] as Array<Number>;

    // a random number per tick
    var st_randomnumber as Number = 0;

    // The FG status bar (screens[4] holds the BG in the C code; here the
    // STBAR patch is the BG, see StLib.V_CopyRect).
    var stbarbitmap as Graphics.BufferedBitmap? = null;

    //
    // STATUS BAR CODE
    //
    function ST_refreshBackground() as Void {
        if (st_statusbaron) {
            // V_DrawPatch(ST_X, 0, BG, sbar) and the copy to FG: the
            // STBAR bitmap is BG already, so just copy it.
            StLib.V_CopyRect(ST_X, StLib.ST_Y, StLib.ST_WIDTH, StLib.ST_HEIGHT);
        }
    }

    // ST_calcPainOffset's statics
    var lastcalc as Number = 0;
    var oldhealth as Number = -1;

    function ST_calcPainOffset() as Number {
        var health;

        health = DPlayer.players_health[plyr] > 100 ? 100 : DPlayer.players_health[plyr];

        if (health != oldhealth) {
            lastcalc = ST_FACESTRIDE * (((100 - health) * ST_NUMPAINFACES) / 101);
            oldhealth = health;
        }
        return lastcalc;
    }

    // ST_updateFaceWidget's statics
    var lastattackdown as Number = -1;
    var priority as Number = 0;

    //
    // This is a not-very-pretty routine which handles
    //  the face states and their timing.
    // the precedence of expressions is:
    //  dead > evil grin > turned head > straight ahead
    //
    function ST_updateFaceWidget() as Void {
        var i;
        var badguyangle;
        var diffang;
        var doevilgrin;
        var p = plyr;
        var mo = DPlayer.players_mo[p];

        if (priority < 10) {
            // dead
            if (DPlayer.players_health[p] == 0) {
                priority = 9;
                st_faceindex = ST_DEADFACE;
                st_facecount = 1;
            }
        }

        if (priority < 9) {
            if (DPlayer.players_bonuscount[p] != 0) {
                // picking up bonus
                doevilgrin = false;

                for (i = 0; i < DoomDef.NUMWEAPONS; i++) {
                    if (oldweaponsowned[i] != DPlayer.players_weaponowned[p * DoomDef.NUMWEAPONS + i]) {
                        doevilgrin = true;
                        oldweaponsowned[i] = DPlayer.players_weaponowned[p * DoomDef.NUMWEAPONS + i];
                    }
                }
                if (doevilgrin) {
                    // evil grin if just picked up weapon
                    priority = 8;
                    st_facecount = ST_EVILGRINCOUNT;
                    st_faceindex = ST_calcPainOffset() + ST_EVILGRINOFFSET;
                }
            }
        }

        if (priority < 8) {
            var attacker = DPlayer.players_attacker[p];
            if (DPlayer.players_damagecount[p] != 0
                && attacker != -1
                && attacker != mo) {
                // being attacked
                priority = 7;

                if (DPlayer.players_health[p] - st_oldhealth > ST_MUCHPAIN) {
                    st_facecount = ST_TURNCOUNT;
                    st_faceindex = ST_calcPainOffset() + ST_OUCHOFFSET;
                } else {
                    badguyangle = RMain.R_PointToAngle2(PMobj.mobjs_x[mo],
                                                        PMobj.mobjs_y[mo],
                                                        PMobj.mobjs_x[attacker],
                                                        PMobj.mobjs_y[attacker]);

                    var moangle = PMobj.mobjs_angle[mo];
                    if (DoomType.UGT(badguyangle, moangle)) {
                        // whether right or left
                        diffang = badguyangle - moangle;
                        i = DoomType.UGT(diffang, Tables.ANG180);
                    } else {
                        // whether left or right
                        diffang = moangle - badguyangle;
                        i = DoomType.ULE(diffang, Tables.ANG180);
                    } // confusing, aint it?

                    st_facecount = ST_TURNCOUNT;
                    st_faceindex = ST_calcPainOffset();

                    if (DoomType.ULT(diffang, Tables.ANG45)) {
                        // head-on
                        st_faceindex += ST_RAMPAGEOFFSET;
                    } else if (i) {
                        // turn face right
                        st_faceindex += ST_TURNOFFSET;
                    } else {
                        // turn face left
                        st_faceindex += ST_TURNOFFSET + 1;
                    }
                }
            }
        }

        if (priority < 7) {
            // getting hurt because of your own damn stupidity
            if (DPlayer.players_damagecount[p] != 0) {
                if (DPlayer.players_health[p] - st_oldhealth > ST_MUCHPAIN) {
                    priority = 7;
                    st_facecount = ST_TURNCOUNT;
                    st_faceindex = ST_calcPainOffset() + ST_OUCHOFFSET;
                } else {
                    priority = 6;
                    st_facecount = ST_TURNCOUNT;
                    st_faceindex = ST_calcPainOffset() + ST_RAMPAGEOFFSET;
                }
            }
        }

        if (priority < 6) {
            // rapid firing
            if (DPlayer.players_attackdown[p] != 0) {
                if (lastattackdown == -1) {
                    lastattackdown = ST_RAMPAGEDELAY;
                } else {
                    lastattackdown--;
                    if (lastattackdown == 0) {
                        priority = 5;
                        st_faceindex = ST_calcPainOffset() + ST_RAMPAGEOFFSET;
                        st_facecount = 1;
                        lastattackdown = 1;
                    }
                }
            } else {
                lastattackdown = -1;
            }
        }

        if (priority < 5) {
            // invulnerability
            if ((DPlayer.players_cheats[p] & DPlayer.CF_GODMODE) != 0
                || DPlayer.players_powers[p * DoomDef.NUMPOWERS + DoomDef.pw_invulnerability] != 0) {
                priority = 4;

                st_faceindex = ST_GODFACE;
                st_facecount = 1;
            }
        }

        // look left or look right if the facecount has timed out
        if (st_facecount == 0) {
            st_faceindex = ST_calcPainOffset() + (st_randomnumber % 3);
            st_facecount = ST_STRAIGHTFACECOUNT;
            priority = 0;
        }

        st_facecount--;
    }

    function ST_updateWidgets() as Void {
        var i;
        var p = plyr;

        // must redirect the pointer if the ready weapon has changed.
        var ammo = DItems.weaponinfo[DPlayer.players_readyweapon[p] * DItems.WI_SIZE + DItems.WI_AMMO];
        if (ammo == DoomDef.am_noammo) {
            w_ready_ammo = -1; // &largeammo
        } else {
            w_ready_ammo = ammo;
        }
        w_ready.data = DPlayer.players_readyweapon[p];

        // update keycard multiple widgets
        for (i = 0; i < 3; i++) {
            keyboxes[i] = DPlayer.players_cards[p * DoomDef.NUMCARDS + i] != 0 ? i : -1;

            if (DPlayer.players_cards[p * DoomDef.NUMCARDS + i + 3] != 0) {
                keyboxes[i] = i + 3;
            }
        }

        // refresh everything if this is him coming back to life
        ST_updateFaceWidget();

        // used by the w_armsbg widget
        st_notdeathmatch = !DoomStat.deathmatch;

        // used by w_arms[] widgets
        st_armson = st_statusbaron && !DoomStat.deathmatch;

        // used by w_frags widget
        st_fragson = DoomStat.deathmatch && st_statusbaron;
        st_fragscount = 0;

        for (i = 0; i < DoomStat.MAXPLAYERS; i++) {
            if (i != DPlayer.consoleplayer) {
                st_fragscount += DPlayer.players_frags[p * DoomStat.MAXPLAYERS + i];
            } else {
                st_fragscount -= DPlayer.players_frags[p * DoomStat.MAXPLAYERS + i];
            }
        }

        // get rid of chat window if up because of message
        st_msgcounter--;
        if (st_msgcounter == 0) {
            st_chat = st_oldchat;
        }
    }

    function ST_Ticker() as Void {
        st_clock++;
        st_randomnumber = MRandom.M_Random();
        ST_updateWidgets();
        st_oldhealth = DPlayer.players_health[plyr];
    }

    var st_palette as Number = 0;

    // ST_doPaletteStuff picks the palette; I_SetPalette has nothing to
    // set on the watch, so the view reads st_palette and tints instead.
    function ST_doPaletteStuff() as Void {
        var palette;
        var cnt;
        var bzc;
        var p = plyr;

        cnt = DPlayer.players_damagecount[p];

        var strength = DPlayer.players_powers[p * DoomDef.NUMPOWERS + DoomDef.pw_strength];
        if (strength != 0) {
            // slowly fade the berzerk out
            bzc = 12 - (strength >> 6);

            if (bzc > cnt) {
                cnt = bzc;
            }
        }

        var ironfeet = DPlayer.players_powers[p * DoomDef.NUMPOWERS + DoomDef.pw_ironfeet];
        if (cnt != 0) {
            palette = (cnt + 7) >> 3;

            if (palette >= NUMREDPALS) {
                palette = NUMREDPALS - 1;
            }

            palette += STARTREDPALS;
        } else if (DPlayer.players_bonuscount[p] != 0) {
            palette = (DPlayer.players_bonuscount[p] + 7) >> 3;

            if (palette >= NUMBONUSPALS) {
                palette = NUMBONUSPALS - 1;
            }

            palette += STARTBONUSPALS;
        } else if (ironfeet > 4 * 32
                   || (ironfeet & 8) != 0) {
            palette = RADIATIONPAL;
        } else {
            palette = 0;
        }

        if (palette != st_palette) {
            st_palette = palette;
            // I_SetPalette (pal);
        }
    }

    // The pointer derefs: copy the values the widgets point at into them.
    function ST_readWidgetValues() as Void {
        var p = plyr;
        var i;

        w_ready.num = w_ready_ammo == -1 ? 1994 : DPlayer.players_ammo[p * DoomDef.NUMAMMO + w_ready_ammo];
        w_ready.on = st_statusbaron;
        for (i = 0; i < 4; i++) {
            w_ammo[i].num = DPlayer.players_ammo[p * DoomDef.NUMAMMO + i];
            w_ammo[i].on = st_statusbaron;
            w_maxammo[i].num = DPlayer.players_maxammo[p * DoomDef.NUMAMMO + i];
            w_maxammo[i].on = st_statusbaron;
        }
        w_health.n.num = DPlayer.players_health[p];
        w_health.n.on = st_statusbaron;
        w_armor.n.num = DPlayer.players_armorpoints[p];
        w_armor.n.on = st_statusbaron;
        w_armsbg.val = st_notdeathmatch;
        w_armsbg.on = st_statusbaron;
        for (i = 0; i < 6; i++) {
            w_arms[i].inum = DPlayer.players_weaponowned[p * DoomDef.NUMWEAPONS + i + 1];
            w_arms[i].on = st_armson;
        }
        w_faces.inum = st_faceindex;
        w_faces.on = st_statusbaron;
        for (i = 0; i < 3; i++) {
            w_keyboxes[i].inum = keyboxes[i];
            w_keyboxes[i].on = st_statusbaron;
        }
        w_frags.num = st_fragscount;
        w_frags.on = st_fragson;
    }

    function ST_drawWidgets(refresh as Boolean) as Void {
        var i;

        // used by w_arms[] widgets
        st_armson = st_statusbaron && !DoomStat.deathmatch;

        // used by w_frags widget
        st_fragson = DoomStat.deathmatch && st_statusbaron;

        ST_readWidgetValues();

        StLib.STlib_updateNum(w_ready, refresh);

        for (i = 0; i < 4; i++) {
            StLib.STlib_updateNum(w_ammo[i], refresh);
            StLib.STlib_updateNum(w_maxammo[i], refresh);
        }

        StLib.STlib_updatePercent(w_health, refresh);
        StLib.STlib_updatePercent(w_armor, refresh);

        StLib.STlib_updateBinIcon(w_armsbg, refresh);

        for (i = 0; i < 6; i++) {
            StLib.STlib_updateMultIcon(w_arms[i], refresh);
        }

        StLib.STlib_updateMultIcon(w_faces, refresh);

        for (i = 0; i < 3; i++) {
            StLib.STlib_updateMultIcon(w_keyboxes[i], refresh);
        }

        StLib.STlib_updateNum(w_frags, refresh);
    }

    function ST_doRefresh() as Void {
        st_firsttime = false;

        // draw status bar background to off-screen buff
        ST_refreshBackground();

        // and refresh all widgets
        ST_drawWidgets(true);
    }

    function ST_diffDraw() as Void {
        // update all widgets
        ST_drawWidgets(false);
    }

    function ST_Drawer(fullscreen as Boolean, refresh as Boolean) as Void {
        if (st_stopped || st_clock == 0) {
            // No level yet, or no ST_Ticker since ST_Start: the C game
            // loop always runs a tic before the first draw, which sets
            // st_notdeathmatch and friends. The view here can draw first.
            return;
        }

        st_statusbaron = (!fullscreen); // || automapactive (there's no automap)
        st_firsttime = st_firsttime || refresh;

        // Do red-/gold-shifts from damage/items
        ST_doPaletteStuff();

        if (!st_statusbaron) {
            return;
        }

        StLib.dc = (stbarbitmap as Graphics.BufferedBitmap).getDc();

        // If just after ST_Start(), refresh all
        if (st_firsttime) {
            ST_doRefresh();
        // Otherwise, update as little as possible
        } else {
            ST_diffDraw();
        }

        StLib.dc = null;
    }

    function ST_loadGraphics() as Void {
        var i;

        // The patch data is loaded by StLib.W_CachePatch when first
        // drawn; here are the patch lists.

        // Load the numbers, tall and short
        tallnum = new [10] as Array<Number>;
        shortnum = new [10] as Array<Number>;
        for (i = 0; i < 10; i++) {
            tallnum[i] = HudLumps.TALLNUM + i;
            shortnum[i] = HudLumps.SHORTNUM + i;
        }

        // key cards
        keys = new [DoomDef.NUMCARDS] as Array<Number>;
        for (i = 0; i < DoomDef.NUMCARDS; i++) {
            keys[i] = HudLumps.KEYS + i;
        }

        // arms ownership widgets
        arms = new [6] as Array<Array<Number> >;
        for (i = 0; i < 6; i++) {
            // gray #, yellow #
            arms[i] = [HudLumps.GREYNUM + i + 2, shortnum[i + 2]] as Array<Number>;
        }

        // face states, in ST_loadGraphics' order (see hud2ciq.py)
        faces = new [ST_NUMFACES] as Array<Number>;
        for (i = 0; i < ST_NUMFACES; i++) {
            faces[i] = HudLumps.FACES + i;
        }

        // The status bar's FG copy is a bitmap of its own here.
        var ref = Graphics.createBufferedBitmap({:width => StLib.ST_WIDTH, :height => StLib.ST_HEIGHT});
        stbarbitmap = ref.get() as Graphics.BufferedBitmap;
    }

    function ST_loadData() as Void {
        ST_loadGraphics();
    }

    function ST_initData() as Void {
        var i;

        st_firsttime = true;
        plyr = DPlayer.consoleplayer;

        st_clock = 0;

        st_statusbaron = true;
        st_oldchat = false;
        st_chat = false;

        st_faceindex = 0;
        st_palette = -1;

        st_oldhealth = -1;

        for (i = 0; i < DoomDef.NUMWEAPONS; i++) {
            oldweaponsowned[i] = DPlayer.players_weaponowned[plyr * DoomDef.NUMWEAPONS + i];
        }

        for (i = 0; i < 3; i++) {
            keyboxes[i] = -1;
        }

        StLib.STlib_init();
    }

    function ST_createWidgets() as Void {
        var i;
        var p = plyr;

        // ready weapon ammo
        w_ready = new st_number_t();
        var ammo = DItems.weaponinfo[DPlayer.players_readyweapon[p] * DItems.WI_SIZE + DItems.WI_AMMO];
        // (the C code points at ammo[am_noammo] here, past the ammo
        // array, until ST_updateWidgets redirects it)
        w_ready_ammo = ammo == DoomDef.am_noammo ? -1 : ammo;
        StLib.STlib_initNum(w_ready,
                            ST_AMMOX,
                            ST_AMMOY,
                            tallnum,
                            0,
                            st_statusbaron,
                            ST_AMMOWIDTH);

        // the last weapon type
        w_ready.data = DPlayer.players_readyweapon[p];

        // health percentage
        w_health = new st_percent_t();
        StLib.STlib_initPercent(w_health,
                                ST_HEALTHX,
                                ST_HEALTHY,
                                tallnum,
                                DPlayer.players_health[p],
                                st_statusbaron,
                                HudLumps.TALLPERCENT);

        // arms background
        w_armsbg = new st_binicon_t();
        StLib.STlib_initBinIcon(w_armsbg,
                                ST_ARMSBGX,
                                ST_ARMSBGY,
                                HudLumps.ARMSBG,
                                st_notdeathmatch,
                                st_statusbaron);

        // weapons owned
        w_arms = new [6] as Array<st_multicon_t>;
        for (i = 0; i < 6; i++) {
            w_arms[i] = new st_multicon_t();
            StLib.STlib_initMultIcon(w_arms[i],
                                     ST_ARMSX + (i % 3) * ST_ARMSXSPACE,
                                     ST_ARMSY + (i / 3) * ST_ARMSYSPACE,
                                     arms[i],
                                     DPlayer.players_weaponowned[p * DoomDef.NUMWEAPONS + i + 1],
                                     st_armson);
        }

        // frags sum
        w_frags = new st_number_t();
        StLib.STlib_initNum(w_frags,
                            ST_FRAGSX,
                            ST_FRAGSY,
                            tallnum,
                            st_fragscount,
                            st_fragson,
                            ST_FRAGSWIDTH);

        // faces
        w_faces = new st_multicon_t();
        StLib.STlib_initMultIcon(w_faces,
                                 ST_FACESX,
                                 ST_FACESY,
                                 faces,
                                 st_faceindex,
                                 st_statusbaron);

        // armor percentage - should be colored later
        w_armor = new st_percent_t();
        StLib.STlib_initPercent(w_armor,
                                ST_ARMORX,
                                ST_ARMORY,
                                tallnum,
                                DPlayer.players_armorpoints[p],
                                st_statusbaron, HudLumps.TALLPERCENT);

        // keyboxes 0-2
        var keyy = [ST_KEY0Y, ST_KEY1Y, ST_KEY2Y];
        w_keyboxes = new [3] as Array<st_multicon_t>;
        for (i = 0; i < 3; i++) {
            w_keyboxes[i] = new st_multicon_t();
            StLib.STlib_initMultIcon(w_keyboxes[i],
                                     ST_KEY0X,
                                     keyy[i],
                                     keys,
                                     keyboxes[i],
                                     st_statusbaron);
        }

        // ammo count (all four kinds)
        // max ammo count (all four kinds)
        var ammoy = [ST_AMMO0Y, ST_AMMO1Y, ST_AMMO2Y, ST_AMMO3Y];
        var maxammoy = [ST_MAXAMMO0Y, ST_MAXAMMO1Y, ST_MAXAMMO2Y, ST_MAXAMMO3Y];
        w_ammo = new [4] as Array<st_number_t>;
        w_maxammo = new [4] as Array<st_number_t>;
        for (i = 0; i < 4; i++) {
            w_ammo[i] = new st_number_t();
            StLib.STlib_initNum(w_ammo[i],
                                ST_AMMO0X,
                                ammoy[i],
                                shortnum,
                                DPlayer.players_ammo[p * DoomDef.NUMAMMO + i],
                                st_statusbaron,
                                ST_AMMO0WIDTH);

            w_maxammo[i] = new st_number_t();
            StLib.STlib_initNum(w_maxammo[i],
                                ST_MAXAMMO0X,
                                maxammoy[i],
                                shortnum,
                                DPlayer.players_maxammo[p * DoomDef.NUMAMMO + i],
                                st_statusbaron,
                                ST_MAXAMMO0WIDTH);
        }
    }

    var st_stopped as Boolean = true;

    function ST_Start() as Void {
        if (veryfirsttime != 0) {
            // D_DoomMain's ST_Init, done on first use instead
            ST_Init();
        }

        if (!st_stopped) {
            ST_Stop();
        }

        ST_initData();
        ST_createWidgets();
        st_stopped = false;
    }

    function ST_Stop() as Void {
        if (st_stopped) {
            return;
        }

        // I_SetPalette (W_CacheLumpNum (lu_palette, PU_CACHE));
        st_palette = 0;

        st_stopped = true;
    }

    function ST_Init() as Void {
        veryfirsttime = 0;
        ST_loadData();
    }
}
