#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
typedef int fixed_t;
#define FRACBITS 16
#define MAXINT INT_MAX
#define MININT INT_MIN
fixed_t FixedMul(fixed_t a, fixed_t b) { return ((long long) a * (long long) b) >> FRACBITS; }
fixed_t FixedDiv2(fixed_t a, fixed_t b) { long long c = ((long long)a<<16) / ((long long)b); return (fixed_t) c; }
fixed_t FixedDiv(fixed_t a, fixed_t b) { if ((abs(a)>>14) >= abs(b)) return (a^b)<0 ? MININT : MAXINT; return FixedDiv2(a,b); }
int SlopeDiv(unsigned num, unsigned den) { unsigned ans; if (den < 512) return 2048; ans = (num<<3)/(den>>8); return ans <= 2048 ? ans : 2048; }
int main(void) {
  int v[][2] = {{65536,65536},{-3*65536,131072},{123456789,-98765},{1<<30,1<<30},{-2147483647,3},{70000,1},{1,-1},{-500000000,7}};
  int n = sizeof v / sizeof v[0];
  for (int i = 0; i < n; i++)
    printf("        [%d, %d, %d, %d],\n", v[i][0], v[i][1], FixedMul(v[i][0], v[i][1]), FixedDiv(v[i][0], v[i][1]));
  unsigned s[][2] = {{0,600},{100,100},{65536,65536},{1u<<30,1u<<29},{3000000000u,1u<<31},{536870911u,4000000u}};
  for (int i = 0; i < 6; i++) printf("        [%d, %d, %d],\n", (int)s[i][0], (int)s[i][1], SlopeDiv(s[i][0], s[i][1]));
}
