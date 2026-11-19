/* A hand-written entry of [pre] answers its second call. The precondition
   reads the validity of an allocated block, which the kernel reports to the
   observers of the metadata of allocated blocks. */

#include <stdlib.h>
int *p;
int g, out;

/*@ requires positive: \valid(p); */
void pre(int x) {
  out = x + 1;
  if (x == 1) {
    /*@ check one: x == 1; */
  }
}

int main(void) {
  p = malloc(sizeof(*p));
  if (!p) return 0;
  g = 1;
  pre(2);
  g = 0;
  pre(1);
  out = 5;
  return 0;
}
