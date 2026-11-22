/* run.config
   ENV: HIT_LOG_OBSERVER_SUMMARY @PTEST_NAME@.summary
   LOG: @PTEST_NAME@.summary
   STDOPT: +"-eva-slevel 100 -eva-unroll-recursive-calls 10"
*/

/* The observer rebuilds the calls below a hit from the calls made by the
   analysed call of each cache entry, not from the calls made on a
   callstack, see children_cycle.c.

   The loop calls f(2), analysed, which calls f(1), then f(0), analysed as
   cache entry A. The call f(0) of b is a hit of A, which makes no call: no
   call is below a hit. Rebuilt from the calls made on the callstack of the
   loop, the call f(1) made by f(2) would be below the hit, and would cross
   a recursion: an unavailable answer there would be wrongly taken for a
   case of the closed list. The observer would print it among the calls
   below a hit that it rebuilds and Eva does not list. */

int f(int n) {
  int x = n, *p = &x;
  if (n == 2) return f(1);
  return *p;
}

int a[2], b;

int main(void) {
  for (int i = 0; i < 2; i++) a[i] = f(i ? 0 : 2);
  b = f(0);
  return 0;
}
