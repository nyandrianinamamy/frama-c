/* A property violated at two visits of a loop and satisfied at the third,
   when x = 1. */

volatile int v;
int g, out;

void body(int x, int y) {
  int i;
  for (i = 0; i < 3; i++) {
    /*@ check mixed: x != 1 || i == 2; */
  }
  if (v) out = 100 / y;
  out = x + g;
}

void producer(void) {
  g = 7;
  body(1, 0);
}

int main(void) {
  g = 7;
  body(2, 1);
  out = 0;
  body(1, 0);
  return 0;
}
