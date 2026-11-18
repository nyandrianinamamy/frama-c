/* Calls answered with no cache, and calls whose analysis is interrupted. */

volatile int nondet;

int leaf(int x) {
  return x + 1;
}

int divide(int x) {
  return 10 / x;
}

int main(void) {
  int a = leaf(1);
  int b = leaf(1);
  int c = divide(nondet);
  return a + b + c;
}
