/* The alarms of [body] have predicates that the kernel builds with a cast,
   for the unaligned pointer, and with a built-in predicate of the logic,
   for the float that is not finite. The analysis from [main] has not
   registered them before its call of [body]. */

volatile int v;
int *ip;
double fp;
int g, out, r1, r2;

void body(int x, int y) {
  if (v) ip = (int *)2;
  if (v) fp = 0.0 / 0.0;
  out = x + g;
}

void producer(void) {
  g = 7;
  body(1, 0);
}

int main(void) {
  g = 7;
  r1 = out;
  out = 0;
  body(1, 0);
  r2 = out;
  return 0;
}
