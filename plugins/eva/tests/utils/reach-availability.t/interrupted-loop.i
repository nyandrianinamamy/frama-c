/* The unrolled loop calls f twice from one site, on one callstack. The
   first visit, with x = 0, reaches R; the second one, with x = 1, calls
   stop_analysis before R. Nothing after the loop was analyzed. */

int g;

void stop_analysis(void) {}

void f(int x) {
  if (x == 1)
    stop_analysis();
R:
  g = x;
}

int main(void) {
  /*@ loop unroll 2; */
  for (int i = 0; i < 2; i++)
    f(i);
L:
  return g;
}
