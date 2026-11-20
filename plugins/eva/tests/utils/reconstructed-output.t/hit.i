/* f reads x only: with memexec, its second call is a hit on the entry of
   the first, although g differs. h is recursive, and only partially
   analyzed. */

int g, y, z;

static int f(int x) {
  y = x + 1;
  return y;
}

/*@ assigns z, \result \from n; */
int h(int n) {
  if (n <= 0)
    return 0;
  z = n;
  return h(n - 1) + 1;
}

int main(void) {
  g = 4;
  f(10);
  g = 9;
  f(10);
  return h(2) + g;
}
