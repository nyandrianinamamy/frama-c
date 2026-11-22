/* run.config
   ENV: HIT_LOG_OBSERVER_SUMMARY @PTEST_NAME@.summary
   LOG: @PTEST_NAME@.summary
   STDOPT: +"-eva-unroll-recursive-calls 10"
*/

/* Points below a call that crosses a recursion. f takes the address of x
   and calls itself once: the second call f(1) is a hit, and below it, the
   recursive call f(0) renames x. Its start is unavailable, and so are the
   points of leaf called by f(0) that its cache entry reaches, here R. Dead
   is not reached by the cache entry of leaf: it stays unreachable, since
   the hit matched the inputs that decide it. No callstack reaches Dead, and
   its joined state, which includes the callstack below the hit, is
   unreachable. The summary of the observer is printed to show the case it
   gives to each unavailable answer. */

int a, b, z;

void leaf(int v) {
 R:
  if (v == 7) {
  Dead:
    z = 7;
  }
}

int f(int n) {
  int x = n, *p = &x;
  if (n) return f(n - 1);
  leaf(*p);
  return *p;
}

int main(void) {
  a = f(1);
  b = f(1);
  return 0;
}
