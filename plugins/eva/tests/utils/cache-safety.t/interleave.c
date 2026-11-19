/* At x = 1, a signed overflow: an alarm under -warn-signed-overflow, and
   otherwise the assumption of 2's complement, in the category
   signed-overflow. */

volatile int v;
int g, out;

void body(int x) {
  /*@ check first: x == 0; */
  if (x == 1 && v) out = 2147483647 + x;
  /*@ check last: x == 0; */
  out = x + g;
}

void producer(void) {
  g = 7;
  body(1);
}

int main(void) {
  g = 7;
  body(1);
  return 0;
}
