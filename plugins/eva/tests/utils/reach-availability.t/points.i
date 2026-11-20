/* Reached and unreachable points, a nonterminating call, and calls
   interpreted by a specification (-eva-use-spec by_spec) or a builtin
   (floor). */

volatile int nondet;
int g, h;

/*@ assigns \result \from x; ensures \result == x + 1; */
int by_spec(int x) {
S:
  return x + 1;
}

/*@ assigns \result \from x; */
double floor(double x) {
B:
  return x;
}

void spin(void) {
  while (1)
    h++;
N:
  h = -1;
}

int f(int x) {
  if (x < 0) {
U:
    g = -1;
  }
P:
  g = x;
  return g;
}

int main(void) {
  f(1);
  f(2);
  int r = by_spec(3);
  double d = floor(2.5);
  if (nondet) {
C:
    spin();
D:
    g = r;
  }
  return g + (int)d;
}
