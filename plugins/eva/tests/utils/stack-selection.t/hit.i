/* With memexec, the second call to f reuses the first. */

int g, y;

static int f(int x) {
P:
  y = x + 1;
  return y;
}

int main(void) {
  g = 4;
  f(10);
  g = 9;
  y = 0;
  f(10);
  return g + y;
}
