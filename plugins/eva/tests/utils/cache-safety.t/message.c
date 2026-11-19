/* The messages that accompany the statuses of a body. */

volatile int v;
int g, out;

/*@ ensures post: out == x + 7; */
void body(int x, int y) {
  if (v) {
    /*@ assert two: x == 2; */
  }
  out = y;
  out = x + g;
}

void producer(void) {
  g = 7;
  body(1, 0);
}

/* body(2, v & 1) is analysed and emits no warning; body(1, 0) is a hit. */
int main(void) {
  g = 7;
  body(2, v & 1);
  out = 0;
  body(1, 0);
  return 0;
}
