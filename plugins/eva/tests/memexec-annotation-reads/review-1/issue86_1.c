int g, y, r1, r2;

/*@ requires x >= g; */
static int f(int x) {
  y = x + 1;
  return y;
}

int main(int n) {
  int v = n;
  g = 9;
  r1 = f(v);
  v = n;
  g = 4; y = 0;
  r2 = f(v);
  return 0;
}
