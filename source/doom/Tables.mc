// tables.c / tables.h
//
// Lookup tables. The values themselves are extracted from the original
// tables.c by tools/tables2ciq.py and loaded as jsonData by Tables_Init.

import Toybox.Lang;
import Toybox.WatchUi;

module Tables {

    const FINEANGLES = 8192;
    const FINEMASK = FINEANGLES - 1;

    // 0x100000000 to 0x2000
    const ANGLETOFINESHIFT = 19;

    // Binary Angle Measument, BAM.
    const ANG45 = 0x20000000;
    const ANG90 = 0x40000000;
    const ANG180 = 0x80000000;
    const ANG270 = 0xc0000000;

    const SLOPERANGE = 2048;
    const SLOPEBITS = 11;
    const DBITS = MFixed.FRACBITS - SLOPEBITS;

    // Effective size is 10240. finecosine is &finesine[FINEANGLES/4] in
    // the C code; Monkey C has no pointers into arrays, so callers index
    // finesine[FINECOSINE + n] instead.
    var finesine as Array<Number> = [] as Array<Number>;
    const FINECOSINE = FINEANGLES / 4;

    // Effective size is 4096.
    var finetangent as Array<Number> = [] as Array<Number>;

    // Effective size is 2049;
    // The +1 size is to handle the case when x==y
    //  without additional checking.
    var tantoangle as Array<Number> = [] as Array<Number>;

    function Tables_Init() as Void {
        finesine = WatchUi.loadResource(Rez.JsonData.finesine) as Array<Number>;
        finetangent = WatchUi.loadResource(Rez.JsonData.finetangent) as Array<Number>;
        tantoangle = WatchUi.loadResource(Rez.JsonData.tantoangle) as Array<Number>;
    }

    function SlopeDiv(num as Number, den as Number) as Number {
        if (DoomType.ULT(den, 512)) {
            return SLOPERANGE;
        }

        // (num<<3)/(den>>8) in 32-bit unsigned arithmetic.
        var ans = ((DoomType.UNSIGNED(num) << 3) & 0xffffffffl) / (DoomType.UNSIGNED(den) >> 8);

        return ans <= SLOPERANGE ? ans.toNumber() : SLOPERANGE;
    }
}
