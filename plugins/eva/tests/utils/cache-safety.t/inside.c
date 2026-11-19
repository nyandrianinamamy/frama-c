/* At x = 1, a signed overflow: an alarm under -warn-signed-overflow, and
   otherwise the assumption of 2's complement, in the category
   signed-overflow. */

volatile int v;
int g, out;

void body(int x) {
  if (x == 1 && v) out = 2147483647 + x;
  /*@ check later: x == 0; */
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
