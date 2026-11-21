/* run.config
   PLUGIN: eva
   STDOPT:
*/

/* Without InOut, no footprint is given: the points of the bodies are
   unavailable, the starts of the functions are answered. */

int g, h, out;

void f(void) { P: out = g; }

int main(void) {
  g = 1; h = 7; f();
  g = 1; h = 8; f();
  return 0;
}
