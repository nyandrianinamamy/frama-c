/* At x = 1, the check later fails at each of the three iterations of
   the loop. */

volatile int v;
int g, out;

void body(int x) {
  for (int i=0; i < 3; ++i) {
    /*@ check later: x == 0; */
  }
  out = x + g;
}

void other(void) {
  /*@ check trigger: g == 0; */
}

int main(void) {
  g = 7;
  body(1);
  other();
  body(1);
  return 0;
}
