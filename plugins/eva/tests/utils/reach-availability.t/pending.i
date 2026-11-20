/* While the analysis runs, f calls pending_probe: the driver then makes
   requests on the stack of f, before any result is available. */

int g;

void pending_probe(void) {}

int f(int x) {
  pending_probe();
P:
  g = x;
  return g;
}

int main(void) {
  f(1);
  return g;
}
