/* The analysis stops in the third call to f, when f calls stop_analysis.
   The first two calls completed and reached R, with x = 1 and x = 3; the
   third one stopped before R. Nothing after the third call was analyzed. */

int g;

void stop_analysis(void) {}

int f(int x) {
  if (x == 2)
    stop_analysis();
R:
  g = x;
  return g;
}

int main(void) {
  f(1);
  f(3);
  f(2);
L:
  g = 4;
  return g;
}
