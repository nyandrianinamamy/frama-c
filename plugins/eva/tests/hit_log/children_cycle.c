/* run.config
   ENV: HIT_LOG_OBSERVER_SUMMARY @PTEST_NAME@.summary
   LOG: @PTEST_NAME@.summary
   STDOPT: +"-eva-slevel 100 -eva-unroll-recursive-calls 10"
*/

/* The observer rebuilds the calls below a hit from the calls made by the
   analysed call of each cache entry, not from the calls made on a
   callstack: two calls on one callstack can compute two cache entries that
   make different calls.

   The loop calls f(0), analysed as cache entry A, then f(1), analysed as
   cache entry B. The recursive call f(0) made by f(1) is a hit of A. The
   call f(1) of b is a hit of B. Below it, f(0) is a recursive call that
   renames x: its start is unavailable. A has no call below it, although
   the hit of A made by f(1) is on the callstack of f(0) in the loop.
   Rebuilt from the calls made on that callstack, A would call itself, and
   the rebuilding would not end. The summary of the observer is printed to
   show the case it gives to each unavailable answer. */

int f(int n) {
  int x = n, *p = &x;
  if (n) return f(0);
  return *p;
}

int a[2], b;

int main(void) {
  for (int i = 0; i < 2; i++) a[i] = f(i);
  b = f(1);
  return 0;
}
