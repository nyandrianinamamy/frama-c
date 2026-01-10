/* Test of the request returning the states inferred by the analysis.
   See test_request.ml for details. */

volatile int nondet;

int g = 1;
int h;

void main (void) {
  int x = nondet % 10;
  g = 10;
  int z = x + g;
  return;
}
