/* The assertion of f reads *p in the Pre state. The input of each call has
   p in {&a; &b}; the precondition of f reduces it to &a. main calls f twice
   with the same input. */

int a, b, *p, y;

/*@ requires p == &a; */
static int f(int x) {
P:
  y = x;
  /*@ assert \at(*p, Pre) >= 0; */
  return y;
}

int main(int n) {
  int *t[2] = {&a, &b};
  a = 1;
  p = t[n & 1];
  f(10);
  p = t[n & 1];
  f(10);
  return y;
}
