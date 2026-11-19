/* No alarm in body: its entries differ only by their key and by the
   status of the warning categories they carry. */

volatile int v;
int g, out;

void body(int x) {
  if (x == 1 && v) out = 1 + x;
  out = x + g;
}

void other(void) {
  /*@ assert trigger: g == 7; */
}

int main(void) {
  g = 7;
  body(1);
  other();
  body(1);
  return 0;
}
