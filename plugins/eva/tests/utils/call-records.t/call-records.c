/* Messages of the category "cache" with their callstacks, and counts of the
   applications of the allocation builtins. */

#include <stdlib.h>

int leaf(int x) {
  return x + 1;
}

int outer(int x) {
  return leaf(x) + leaf(x);
}

int *alloc(void) {
  return malloc(sizeof(int));
}

int main(void) {
  int a = outer(1);
  int b = outer(1);
  int *p = alloc();
  int *q = alloc();
  free(p);
  free(q);
  return a + b;
}
