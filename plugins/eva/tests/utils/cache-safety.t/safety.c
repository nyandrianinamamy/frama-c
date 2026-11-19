/* The Safety part of the entry of [body] produced by an analysis from
   [producer], delivered at a hit in [main]. */

volatile int v;
int g, out, r1, r2;

void body(int x, int y) {
  if (v) {
    /*@ assert two: x == 2; */
  }
  if (v) out = 100 / y;
  out = x + g;
  /*@ assert ok: out == x + 7; */
}

void producer(void) {
  g = 7;
  body(1, 0);
}

int main(void) {
  g = 7;
  body(2, v & 1);
  r1 = out;
  out = 0;
  body(1, 0);
  r2 = out;
  return 0;
}

/* As main, but the analysed call of body never divides by zero. */
int main2(void) {
  g = 7;
  body(2, 1);
  r1 = out;
  out = 0;
  body(1, 0);
  r2 = out;
  return 0;
}

/* Not called: its call of body is the frame of a delivered write. */
void outer(void) {
  body(1, 0);
}
