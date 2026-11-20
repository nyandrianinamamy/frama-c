/* interrupted.i with the label Q on the first statement of f, which both
   calls reach: the second call reaches Q, then stops before R. */

int g;

void stop_analysis(void) {}

int f(int x) {
Q:
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
