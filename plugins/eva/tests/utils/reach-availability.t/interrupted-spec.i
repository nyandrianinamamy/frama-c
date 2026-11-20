/* by_spec is interpreted by its specification (-eva-use-spec by_spec) and
   floor by its builtin; the analysis then stops when f calls
   stop_analysis. Their bodies are not analyzed on the recorded callstacks;
   the rest of the analysis could have called them again. */

int g;

void stop_analysis(void) {}

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

void f(void) {
  stop_analysis();
}

int main(void) {
  int r = by_spec(3);
  double d = floor(2.5);
  f();
  g = r;
  return g + (int)d;
}
