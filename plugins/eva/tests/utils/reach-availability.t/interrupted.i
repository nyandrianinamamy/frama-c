/* The analysis stops in the second call to f, when f calls stop_analysis.
   The first call to f completed and reached R; the second one stopped
   before R. Nothing after the second call was analyzed. */

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
  f(2);
L:
  g = 3;
  return g;
}
