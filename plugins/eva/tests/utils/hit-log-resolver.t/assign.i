/* Two calls to f enter with g = 4 and g = 9. P labels a straight-line
   assignment. */

int g, y;

static int f(int x) {
P:
  y = x + 1;
  return y;
}

int main(void) {
  g = 4;
  y = 0;
  f(10);
  g = 9;
  y = 0;
  f(10);
  return g + y;
}
