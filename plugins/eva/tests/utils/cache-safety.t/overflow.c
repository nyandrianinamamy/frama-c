/* A signed overflow, reported only when the kernel option
   -warn-signed-overflow is set. */

volatile int v;
int g, out;

void body(int x) {
  if (x == 1 && v) out = 2147483647 + x;
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
