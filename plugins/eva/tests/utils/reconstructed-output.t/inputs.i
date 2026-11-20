/* The script supplies the initial memory, with y = 0 and g = 7 or 3, and
   the argument n of main. Two calls to f enter with g = 4 and g = 9. The
   statement labelled D is unreachable when n >= 0. The checks hold when
   the label Init denotes the supplied memory with g = 7. */

int g, y;

static int f(int x) {
  /*@ check f_init: \at(g, Init) == 7; */
  y = x + g;
P:
  return y;
}

int main(int n) {
  /*@ check main_init: \at(g, Init) == 7 && \at(y, Init) == 0; */
  if (n < 0) {
  D:
    y = 0;
  }
  g = 4;
  f(n);
  g = 9;
  f(n);
  return y;
}
