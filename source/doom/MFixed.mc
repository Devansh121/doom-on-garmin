// m_fixed.c / m_fixed.h
//
// Fixed point, 32bit as 16.16.

import Toybox.Lang;

module MFixed {

    const FRACBITS = 16;
    const FRACUNIT = 1 << FRACBITS;

    // ((long long) a * b) >> FRACBITS, kept to 32 bits like the C cast.
    //
    // Done in halves instead of with a Long: on the watch a Long multiply
    // costs about 5x a Number one. With a = ah<<16 + al and b = bh<<16 +
    // bl (al, bl unsigned 16-bit), the result is
    // ah*bh<<16 + ah*bl + al*bh + (al*bl)>>16, and every term wraps
    // modulo 2^32 the same way the truncating cast does.
    function FixedMul(a as Number, b as Number) as Number {
        var ah = a >> 16;
        var al = a & 0xffff;
        var bh = b >> 16;
        var bl = b & 0xffff;
        return ((ah * bh) << 16) + ah * bl + al * bh + (((al * bl) >> 16) & 0xffff);
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
