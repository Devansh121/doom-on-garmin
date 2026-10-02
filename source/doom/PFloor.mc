// p_floor.c
//
// Floor animation: raising stairs.
//
// A floormove_t is a PTick thinker (TF_MOVEFLOOR) whose fields are
// PTick.thinkers_data[floor][FM_*], in the struct's order.

import Toybox.Lang;

(:extendedCode)
module PFloor {

    // floormove_t fields
    const FM_TYPE = 0;              // floor_e
    const FM_CRUSH = 1;             // boolean, 0 or 1
    const FM_SECTOR = 2;            // sector_t*
    const FM_DIRECTION = 3;
    const FM_NEWSPECIAL = 4;
    const FM_TEXTURE = 5;           // a flat number
    const FM_FLOORDESTHEIGHT = 6;
    const FM_SPEED = 7;
    const FM_SIZE = 8;

    // Z_Malloc (sizeof(*floor), PU_LEVSPEC, 0) for a floormove_t. The
    // fields start at 0 rather than whatever the zone had in it.
    function newFloorMove() as Array<Number> {
        return [0, 0, 0, 0, 0, 0, 0, 0] as Array<Number>;
    }

    // floor = Z_Malloc (sizeof(*floor), PU_LEVSPEC, 0);
    // P_AddThinker (&floor->thinker);
    // sec->specialdata = floor;
    // floor->thinker.function.acp1 = (actionf_p1) T_MoveFloor;
    function newFloor(sec as Number) as Number {
        var floor = PTick.P_AllocThinker();
        PTick.thinkers_data[floor] = newFloorMove();
        PTick.P_AddThinker(floor);
        PSetup.sectors_specialdata[sec] = floor;
        PTick.thinkers_function[floor] = PTick.TF_MOVEFLOOR;
        return floor;
    }

    //
    // FLOORS
    //

    //
    // Move a plane (floor or ceiling) and check for crushing
    //
    function T_MovePlane(sector as Number, speed as Number, dest as Number, crush as Boolean, floorOrCeiling as Number, direction as Number) as Number {
        var flag;
        var lastpos;
        var floorheight = PSetup.sectors_floorheight;
        var ceilingheight = PSetup.sectors_ceilingheight;

        switch (floorOrCeiling) {
            case 0:
                // FLOOR
                switch (direction) {
                    case -1:
                        // DOWN
                        if (floorheight[sector] - speed < dest) {
                            lastpos = floorheight[sector];
                            floorheight[sector] = dest;
                            flag = PMap.P_ChangeSector(sector, crush);
                            if (flag == true) {
                                floorheight[sector] = lastpos;
                                PMap.P_ChangeSector(sector, crush);
                                //return crushed;
                            }
                            return PSpec.pastdest;
                        } else {
                            lastpos = floorheight[sector];
                            floorheight[sector] -= speed;
                            flag = PMap.P_ChangeSector(sector, crush);
                            if (flag == true) {
                                floorheight[sector] = lastpos;
                                PMap.P_ChangeSector(sector, crush);
                                return PSpec.crushed;
                            }
                        }
                        break;

                    case 1:
                        // UP
                        if (floorheight[sector] + speed > dest) {
                            lastpos = floorheight[sector];
                            floorheight[sector] = dest;
                            flag = PMap.P_ChangeSector(sector, crush);
                            if (flag == true) {
                                floorheight[sector] = lastpos;
                                PMap.P_ChangeSector(sector, crush);
                                //return crushed;
                            }
                            return PSpec.pastdest;
                        } else {
                            // COULD GET CRUSHED
                            lastpos = floorheight[sector];
                            floorheight[sector] += speed;
                            flag = PMap.P_ChangeSector(sector, crush);
                            if (flag == true) {
                                if (crush == true) {
                                    return PSpec.crushed;
                                }
                                floorheight[sector] = lastpos;
                                PMap.P_ChangeSector(sector, crush);
                                return PSpec.crushed;
                            }
                        }
                        break;
                }
                break;

            case 1:
                // CEILING
                switch (direction) {
                    case -1:
                        // DOWN
                        if (ceilingheight[sector] - speed < dest) {
                            lastpos = ceilingheight[sector];
                            ceilingheight[sector] = dest;
                            flag = PMap.P_ChangeSector(sector, crush);

                            if (flag == true) {
                                ceilingheight[sector] = lastpos;
                                PMap.P_ChangeSector(sector, crush);
                                //return crushed;
                            }
                            return PSpec.pastdest;
                        } else {
                            // COULD GET CRUSHED
                            lastpos = ceilingheight[sector];
                            ceilingheight[sector] -= speed;
                            flag = PMap.P_ChangeSector(sector, crush);

                            if (flag == true) {
                                if (crush == true) {
                                    return PSpec.crushed;
                                }
                                ceilingheight[sector] = lastpos;
                                PMap.P_ChangeSector(sector, crush);
                                return PSpec.crushed;
                            }
                        }
                        break;

                    case 1:
                        // UP
                        if (ceilingheight[sector] + speed > dest) {
                            lastpos = ceilingheight[sector];
                            ceilingheight[sector] = dest;
                            flag = PMap.P_ChangeSector(sector, crush);
                            if (flag == true) {
                                ceilingheight[sector] = lastpos;
                                PMap.P_ChangeSector(sector, crush);
                                //return crushed;
                            }
                            return PSpec.pastdest;
                        } else {
                            lastpos = ceilingheight[sector];
                            ceilingheight[sector] += speed;
                            flag = PMap.P_ChangeSector(sector, crush);
                            // UNUSED
                            // #if 0
                            //  if (flag == true)
                            //  {
                            //      sector->ceilingheight = lastpos;
                            //      P_ChangeSector(sector,crush);
                            //      return crushed;
                            //  }
                            // #endif
                        }
                        break;
                }
                break;
        }
        return PSpec.ok;
    }

    //
    // MOVE A FLOOR TO IT'S DESTINATION (UP OR DOWN)
    //
    function T_MoveFloor(floor as Number) as Void {
        var d = PTick.thinkers_data[floor] as Array<Number>;
        var sector = d[FM_SECTOR];

        var res = T_MovePlane(sector,
                              d[FM_SPEED],
                              d[FM_FLOORDESTHEIGHT],
                              d[FM_CRUSH] != 0, 0, d[FM_DIRECTION]);

        if ((PTick.leveltime & 7) == 0) {
            SSound.S_StartSound(SSound.S_SectorOrigin(sector), SSound.sfx_stnmov);
        }

        if (res == PSpec.pastdest) {
            PSetup.sectors_specialdata[sector] = -1;

            if (d[FM_DIRECTION] == 1) {
                switch (d[FM_TYPE]) {
                    case PSpec.donutRaise:
                        PSetup.sectors_special[sector] = d[FM_NEWSPECIAL];
                        PSetup.sectors_floorpic[sector] = d[FM_TEXTURE];
                    default:
                        break;
                }
            } else if (d[FM_DIRECTION] == -1) {
                switch (d[FM_TYPE]) {
                    case PSpec.lowerAndChange:
                        PSetup.sectors_special[sector] = d[FM_NEWSPECIAL];
                        PSetup.sectors_floorpic[sector] = d[FM_TEXTURE];
                    default:
                        break;
                }
            }
            PTick.P_RemoveThinker(floor);

            SSound.S_StartSound(SSound.S_SectorOrigin(sector), SSound.sfx_pstop);
        }
    }

    //
    // HANDLE FLOOR TYPES
    //
    function EV_DoFloor(line as Number, floortype as Number) as Number {
        var textureheight = RData.textureheight;
        var rtn = 0;

        // while ((secnum = P_FindSectorFromLineTag(line,secnum)) >= 0):
        // Monkey C has no assignment in expressions.
        for (var secnum = PSpec.P_FindSectorFromLineTag(line, -1); secnum >= 0;
             secnum = PSpec.P_FindSectorFromLineTag(line, secnum)) {
            var sec = secnum;

            // ALREADY MOVING?  IF SO, KEEP GOING...
            if (PSetup.sectors_specialdata[sec] != -1) {
                continue;
            }

            // new floor thinker
            rtn = 1;
            var floor = newFloor(sec);
            var d = PTick.thinkers_data[floor] as Array<Number>;
            d[FM_TYPE] = floortype;
            d[FM_CRUSH] = 0;
            var minsize;

            switch (floortype) {
                case PSpec.lowerFloor:
                    d[FM_DIRECTION] = -1;
                    d[FM_SECTOR] = sec;
                    d[FM_SPEED] = PSpec.FLOORSPEED;
                    d[FM_FLOORDESTHEIGHT] = PSpec.P_FindHighestFloorSurrounding(sec);
                    break;

                case PSpec.lowerFloorToLowest:
                    d[FM_DIRECTION] = -1;
                    d[FM_SECTOR] = sec;
                    d[FM_SPEED] = PSpec.FLOORSPEED;
                    d[FM_FLOORDESTHEIGHT] = PSpec.P_FindLowestFloorSurrounding(sec);
                    break;

                case PSpec.turboLower:
                    d[FM_DIRECTION] = -1;
                    d[FM_SECTOR] = sec;
                    d[FM_SPEED] = PSpec.FLOORSPEED * 4;
                    d[FM_FLOORDESTHEIGHT] = PSpec.P_FindHighestFloorSurrounding(sec);
                    if (d[FM_FLOORDESTHEIGHT] != PSetup.sectors_floorheight[sec]) {
                        d[FM_FLOORDESTHEIGHT] += 8 * MFixed.FRACUNIT;
                    }
                    break;

                case PSpec.raiseFloorCrush:
                    d[FM_CRUSH] = 1;
                case PSpec.raiseFloor:
                    d[FM_DIRECTION] = 1;
                    d[FM_SECTOR] = sec;
                    d[FM_SPEED] = PSpec.FLOORSPEED;
                    d[FM_FLOORDESTHEIGHT] = PSpec.P_FindLowestCeilingSurrounding(sec);
                    if (d[FM_FLOORDESTHEIGHT] > PSetup.sectors_ceilingheight[sec]) {
                        d[FM_FLOORDESTHEIGHT] = PSetup.sectors_ceilingheight[sec];
                    }
                    d[FM_FLOORDESTHEIGHT] -= (8 * MFixed.FRACUNIT)
                        * (floortype == PSpec.raiseFloorCrush ? 1 : 0);
                    break;

                case PSpec.raiseFloorTurbo:
                    d[FM_DIRECTION] = 1;
                    d[FM_SECTOR] = sec;
                    d[FM_SPEED] = PSpec.FLOORSPEED * 4;
                    d[FM_FLOORDESTHEIGHT] = PSpec.P_FindNextHighestFloor(sec, PSetup.sectors_floorheight[sec]);
                    break;

                case PSpec.raiseFloorToNearest:
                    d[FM_DIRECTION] = 1;
                    d[FM_SECTOR] = sec;
                    d[FM_SPEED] = PSpec.FLOORSPEED;
                    d[FM_FLOORDESTHEIGHT] = PSpec.P_FindNextHighestFloor(sec, PSetup.sectors_floorheight[sec]);
                    break;

                case PSpec.raiseFloor24:
                    d[FM_DIRECTION] = 1;
                    d[FM_SECTOR] = sec;
                    d[FM_SPEED] = PSpec.FLOORSPEED;
                    d[FM_FLOORDESTHEIGHT] = PSetup.sectors_floorheight[sec] + 24 * MFixed.FRACUNIT;
                    break;
                case PSpec.raiseFloor512:
                    d[FM_DIRECTION] = 1;
                    d[FM_SECTOR] = sec;
                    d[FM_SPEED] = PSpec.FLOORSPEED;
                    d[FM_FLOORDESTHEIGHT] = PSetup.sectors_floorheight[sec] + 512 * MFixed.FRACUNIT;
                    break;

                case PSpec.raiseFloor24AndChange:
                    d[FM_DIRECTION] = 1;
                    d[FM_SECTOR] = sec;
                    d[FM_SPEED] = PSpec.FLOORSPEED;
                    d[FM_FLOORDESTHEIGHT] = PSetup.sectors_floorheight[sec] + 24 * MFixed.FRACUNIT;
                    PSetup.sectors_floorpic[sec] = PSetup.sectors_floorpic[PSetup.lines_sectors[line] & 0xffff];
                    PSetup.sectors_special[sec] = PSetup.sectors_special[PSetup.lines_sectors[line] & 0xffff];
                    break;

                case PSpec.raiseToTexture:
                    minsize = DoomType.MAXINT;

                    d[FM_DIRECTION] = 1;
                    d[FM_SECTOR] = sec;
                    d[FM_SPEED] = PSpec.FLOORSPEED;
                    for (var i = 0; i < PSetup.sectors_linecount[secnum]; i++) {
                        if (PSpec.twoSided(secnum, i) != 0) {
                            var side = PSpec.getSide(secnum, i, 0);
                            var bottomtexture = PSetup.sides_bottomtexture[side];
                            if (bottomtexture >= 0) {
                                if (textureheight[bottomtexture] < minsize) {
                                    minsize = textureheight[bottomtexture];
                                }
                            }
                            side = PSpec.getSide(secnum, i, 1);
                            bottomtexture = PSetup.sides_bottomtexture[side];
                            if (bottomtexture >= 0) {
                                if (textureheight[bottomtexture] < minsize) {
                                    minsize = textureheight[bottomtexture];
                                }
                            }
                        }
                    }
                    d[FM_FLOORDESTHEIGHT] = PSetup.sectors_floorheight[sec] + minsize;
                    break;

                case PSpec.lowerAndChange:
                    d[FM_DIRECTION] = -1;
                    d[FM_SECTOR] = sec;
                    d[FM_SPEED] = PSpec.FLOORSPEED;
                    d[FM_FLOORDESTHEIGHT] = PSpec.P_FindLowestFloorSurrounding(sec);
                    d[FM_TEXTURE] = PSetup.sectors_floorpic[sec];

                    for (var i = 0; i < PSetup.sectors_linecount[secnum]; i++) {
                        if (PSpec.twoSided(secnum, i) != 0) {
                            if (PSetup.sides_sector[PSpec.getSide(secnum, i, 0)] == secnum) {
                                sec = PSpec.getSector(secnum, i, 1);

                                if (PSetup.sectors_floorheight[sec] == d[FM_FLOORDESTHEIGHT]) {
                                    d[FM_TEXTURE] = PSetup.sectors_floorpic[sec];
                                    d[FM_NEWSPECIAL] = PSetup.sectors_special[sec];
                                    break;
                                }
                            } else {
                                sec = PSpec.getSector(secnum, i, 0);

                                if (PSetup.sectors_floorheight[sec] == d[FM_FLOORDESTHEIGHT]) {
                                    d[FM_TEXTURE] = PSetup.sectors_floorpic[sec];
                                    d[FM_NEWSPECIAL] = PSetup.sectors_special[sec];
                                    break;
                                }
                            }
                        }
                    }
                default:
                    break;
            }
        }
        return rtn;
    }

    //
    // BUILD A STAIRCASE!
    //
    function EV_BuildStairs(line as Number, type as Number) as Number {
        var buffer = PSetup.linebuffer;
        var flags = PSetup.lines_flags;
        // frontsector | backsector << 16 (see PSetup)
        var sectors = PSetup.lines_sectors;
        var rtn = 0;
        var speed = 0;
        var stairsize = 0;

        // while ((secnum = P_FindSectorFromLineTag(line,secnum)) >= 0):
        // Monkey C has no assignment in expressions. The loop below moves
        // secnum on to each stair, and the next search starts from there,
        // just like the C code.
        for (var secnum = PSpec.P_FindSectorFromLineTag(line, -1); secnum >= 0;
             secnum = PSpec.P_FindSectorFromLineTag(line, secnum)) {
            var sec = secnum;

            // ALREADY MOVING?  IF SO, KEEP GOING...
            if (PSetup.sectors_specialdata[sec] != -1) {
                continue;
            }

            // new floor thinker
            rtn = 1;
            var floor = newFloor(sec);
            var d = PTick.thinkers_data[floor] as Array<Number>;
            d[FM_DIRECTION] = 1;
            d[FM_SECTOR] = sec;
            switch (type) {
                case PSpec.build8:
                    speed = PSpec.FLOORSPEED / 4;
                    stairsize = 8 * MFixed.FRACUNIT;
                    break;
                case PSpec.turbo16:
                    speed = PSpec.FLOORSPEED * 4;
                    stairsize = 16 * MFixed.FRACUNIT;
                    break;
            }
            d[FM_SPEED] = speed;
            var height = PSetup.sectors_floorheight[sec] + stairsize;
            d[FM_FLOORDESTHEIGHT] = height;

            var texture = PSetup.sectors_floorpic[sec];

            // Find next sector to raise
            // 1.	Find 2-sided line with same sector side[0]
            // 2.	Other side is the next sector to raise
            var ok;
            do {
                ok = 0;
                var first = PSetup.sectors_lines[sec];
                for (var i = 0; i < PSetup.sectors_linecount[sec]; i++) {
                    var l = buffer[first + i];
                    if ((flags[l] & DoomData.ML_TWOSIDED) == 0) {
                        continue;
                    }

                    var tsec = sectors[l] & 0xffff;
                    var newsecnum = tsec;

                    if (secnum != newsecnum) {
                        continue;
                    }

                    tsec = sectors[l] >> 16;
                    newsecnum = tsec;

                    if (PSetup.sectors_floorpic[tsec] != texture) {
                        continue;
                    }

                    height += stairsize;

                    if (PSetup.sectors_specialdata[tsec] != -1) {
                        continue;
                    }

                    sec = tsec;
                    secnum = newsecnum;
                    floor = newFloor(sec);
                    d = PTick.thinkers_data[floor] as Array<Number>;

                    d[FM_DIRECTION] = 1;
                    d[FM_SECTOR] = sec;
                    d[FM_SPEED] = speed;
                    d[FM_FLOORDESTHEIGHT] = height;
                    ok = 1;
                    break;
                }
            } while (ok != 0);
        }
        return rtn;
    }
}
