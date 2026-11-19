extern void Frama_C_show_each_y(int);
int x, y, flag;
int *target;
static void discover(void) {
  /*@ loop widen_hints *target, 13; */
  while (flag > 0) --flag;
}
static int count_y(int n) {
  while (y < n) ++y;
  return y;
}
int main(void) {
  target = &x;
  discover();
  target = &y;
  discover();
  Frama_C_show_each_y(count_y(13));
  return 0;
}
