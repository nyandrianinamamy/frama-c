/* A hand-written entry of [pre] answers its second call, whose
   precondition fails. */

int g, out;

/*@ requires positive: g > 0; */
void pre(int x) {
  out = x + 1;
}

int main(void) {
  g = 1;
  pre(2);
  g = 0;
  pre(1);
  out = 5;
  return 0;
}
