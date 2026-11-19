/* A statement with two alarms. */

volatile int v;
int g, out;

void body(int x, int y) {
  if (v) out = (v + x) / (v & y);
  out = x + g;
}

void producer(void) {
  g = 7;
  body(1, 0);
}

int main(void) {
  g = 7;
  body(1, 0);
  return 0;
}
