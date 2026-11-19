extern void Frama_C_show_each_before(int);
extern void Frama_C_show_each_after(int);
#ifndef HINT_THRESHOLD
#define HINT_THRESHOLD 13
#endif
int x;
static int count(int n) {
  while (x < n) ++x;
  return x;
}
static void discover(int *p) {
  /*@ loop widen_hints *p, HINT_THRESHOLD; */
  while (*p < 0) ++*p;
}
int main(void) {
  x = 0;
  int first = count(13);
  Frama_C_show_each_before(first);
#ifndef WITHOUT_DISCOVERY
  discover(&x);
#endif
  x = 0;
  int second = count(13);
  Frama_C_show_each_after(second);
  return 0;
}
