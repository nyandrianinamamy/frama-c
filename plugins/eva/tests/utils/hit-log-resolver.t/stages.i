/* Stages of the input of an invocation. g is an initialized global and
   main binds its formal n. The precondition of f reduces x; no entry
   survives the precondition of h. */

int g = 3, y;

/*@ requires x >= 5; */
static int f(int x) {
P:
  y = x + g;
  return y;
}

/*@ requires x > 100; */
static int h(int x) {
  y = x;
  return y;
}

int main(int n) {
  int v = n > 0 ? 10 : 2;
  f(v);
  if (n > 5)
    h(v);
  return y;
}
