// m_fixed.c / m_fixed.h
//
// Fixed point, 32bit as 16.16.

import Toybox.Lang;

module MFixed {

    const FRACBITS = 16;
    const FRACUNIT = 1 << FRACBITS;

    function FixedMul(a as Number, b as Number) as Number {
        return ((a.toLong() * b) >> FRACBITS).toNumber();
    }

    function FixedDiv(a as Number, b as Number) as Number {
        if ((abs(a) >> 14) >= abs(b)) {
            return (a ^ b) < 0 ? DoomType.MININT : DoomType.MAXINT;
        }
        return FixedDiv2(a, b);
    }

    // The 64-bit integer variant from the #if 0 block in m_fixed.c; the
    // double version it replaced gives the same truncated result here.
    function FixedDiv2(a as Number, b as Number) as Number {
        return ((a.toLong() << 16) / b).toNumber();
    }

    // C abs(): abs(MININT) stays MININT.
    function abs(a as Number) as Number {
        return a < 0 ? -a : a;
    }
}
