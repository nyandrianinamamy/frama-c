/* A hit delivers the statements its body reaches, its guard outcomes and
   its zones, for its own callstack. */

int g, out;

void body(int x) {
  int l = 1;
  if (x == 1) {
    /*@ assert one: x == 1; */
    out = 1;
  } else {
    out = 2;
  }
  if (x == 3) {
    /*@ assert three: x == 3; */
    out = 3;
  }
  g = x + l;
}

/* The entry of body(1). */
void producer(void) {
  body(1);
}

/* body(2) is analysed; body(1) is a hit, and its callstack is reached only
   through the hit. No call reaches the branch of x == 3. */
int main(void) {
  body(2);
  body(1);
  return 0;
}
