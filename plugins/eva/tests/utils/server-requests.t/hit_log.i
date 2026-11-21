/* The worked example of #87, for the [getValues] request with and without
   option -eva-hit-log. See test_request.ml for details. Calls A (line 15)
   and C (line 17) of f are analysed; calls B (line 16) and D (line 18) are
   hits of the cache entries of A and C. */

volatile unsigned int nondet;

int c, g, h;

void f(void) { if (c) g = 0; P: g = 1; }

int main(void) {
  c = nondet % 2;
  g = 4; h = 7; f();
  g = 4; h = 8; f();
  g = 9; h = 8; f();
  g = 9; h = 5; f();
  return 0;
}
