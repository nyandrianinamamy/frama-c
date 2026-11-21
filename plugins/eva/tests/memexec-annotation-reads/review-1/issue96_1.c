#include "__fc_builtin.h"
int x;
static int count(int n) {
  while (x < n) ++x;
  int answer = (int)Frama_C_abstract_max(x);
  return answer;
}
static void discover(int *p) {
  /*@ loop widen_hints *p, 13; */
  while (*p < 0) ++*p;
}
int main(void) {
  x = 0;
  int first = count(13);
  discover(&x);
  x = 0;
  int second = count(13);
  return second;
}
