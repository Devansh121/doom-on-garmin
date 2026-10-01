// doomtype.h
//
// C's unsigned types (angle_t, the unsigned compares in r_bsp.c, ...) have
// no Monkey C equivalent. Number is a signed 32-bit int with the same
// wraparound as C, so add/sub/mul on unsigned values already give the
// right bits; only compares, division and right shifts need help.

import Toybox.Lang;

module DoomType {

    const MAXINT = 0x7fffffff;
    const MININT = 0x80000000;

    // Unsigned a < b, by flipping the sign bit of both sides.
    function ULT(a as Number, b as Number) as Boolean {
        return (a ^ MININT) < (b ^ MININT);
    }

    function UGT(a as Number, b as Number) as Boolean {
        return (a ^ MININT) > (b ^ MININT);
    }

    function UGE(a as Number, b as Number) as Boolean {
        return (a ^ MININT) >= (b ^ MININT);
    }

    function ULE(a as Number, b as Number) as Boolean {
        return (a ^ MININT) <= (b ^ MININT);
    }

    // Logical (unsigned) right shift. Monkey C's >> is arithmetic.
    function USHR(a as Number, n as Number) as Number {
        return n == 0 ? a : (a >> n) & (MAXINT >> (n - 1));
    }

    // a as an unsigned 32-bit value.
    function UNSIGNED(a as Number) as Long {
        return a.toLong() & 0xffffffffl;
    }
}
