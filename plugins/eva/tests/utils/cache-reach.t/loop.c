/* body(2), then body(1), at the same call site: the hit delivers its
   writes on the callstack of the analysed call, where they are joined with
   those of that call. */

int g, out;

void body(int x) {
  if (x == 1) {
    out = 1;
  } else {
    out = 2;
  }
  g = x;
}

/* The entry of body(1). */
void producer(void) {
  body(1);
}

int main(void) {
  for (int i = 2; i >= 1; i--) {
    body(i);
  }
  return 0;
}
