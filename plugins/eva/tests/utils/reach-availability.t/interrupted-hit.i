/* With memexec, the second call to h is a hit on the first. The second
   call to f then calls stop_analysis: later is never entered. */

int g, x;

void stop_analysis(void);

void h(int n) {
  g = n;
}

void f(int n) {
  h(1);
R:
  x = n;
  if (n == 2) stop_analysis();
}

void later(void) {
Z:
  x = 0;
}

int main(void) {
  f(1);
  f(2);
L:
  later();
  return g;
}
