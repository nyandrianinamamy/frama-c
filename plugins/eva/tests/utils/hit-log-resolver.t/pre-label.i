/* The assertion of f reads *p in the Pre state. */

int a, *p, y;

static int f(int x) {
P:
  y = x;
  /*@ assert \at(*p, Pre) >= 0; */
  return y;
}

int main(void) {
  a = 1;
  p = &a;
  f(10);
  return y;
}
