/* A property violated at every visit of a loop. */

int g, out;

void body(int x) {
  int i;
  for (i = 0; i < 3; i++) {
    /*@ check never: x < 0; */
  }
  out = x + g;
}

void producer(void) {
  g = 7;
  body(1);
}

int main(void) {
  g = 7;
  body(1);
  return 0;
}
