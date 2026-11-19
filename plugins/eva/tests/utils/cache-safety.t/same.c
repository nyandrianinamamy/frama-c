/* A signed overflow at x = 1, reported as the assumption of 2's
   complement under -no-warn-signed-overflow. */

volatile int v;
int g, out;

void body(int x) {
  if (x == 1 && v) out = 2147483647 + x;
  out = x + g;
}

void other(void) {
  /*@ assert trigger: g == 7; */
}

int main(void) {
  g = 7;
  body(1);
  other();
  body(1);
  return 0;
}
