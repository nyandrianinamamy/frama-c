/* No alarm in pre. A hand-written entry of pre is a candidate for its
   call at line 18. */

int g, out;

/*@ requires positive: g > 0; */
void pre(int x) {
  out = x + 1;
  if (x == 1) {
    /*@ check one: x == 1; */
  }
}

int main(void) {
  g = 1;
  pre(2);
  g = 1;
  pre(1);
  out = 5;
  return 0;
}
