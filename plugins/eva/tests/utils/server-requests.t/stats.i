/* Test of Eva requests about analysis state, summary, stats and coverage.
   See test_request.ml for details. */

volatile unsigned int nondet;

void reachable (void) { return; }
void unreachable (void) { return; }
void non_terminating (void) { while(1); }

void coverage (void) {
  int x = 5;
  reachable();
  if (x > 10) unreachable();
  if (nondet) non_terminating();
  return;
}

void alarms (void) {
  int a = nondet;
  int b = a + a;
  int c = 1000 / nondet;
  int d = nondet % 10 + 1;
  /*@ assert a > 0; */
  /*@ assert b > 0; */
  /*@ assert c > 0; */
  /*@ assert d > 0; */
}

void main (void) {
  coverage();
  alarms();
}
