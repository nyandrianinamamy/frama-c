/* Minimal C file used to test Eva without plug-ins inout, callgraph and scope. */

volatile int nondet;

int incr (int x) {
  return x+1;
}

void main (void) {
  int x, y;
  x = nondet % 100;
  y = incr(x); // first analysis
  y = incr(x); // use memexec cache only if the inout plugin is available.
  y = 100 / x; // division by 0 alarm
  y = 100 / x; // redundant alarm, removed only if the scope plugin is available.
}
