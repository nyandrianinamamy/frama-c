/* Loops whose widening reads or updates the validity of an allocated block
   that the loop does not allocate. */

#include <stdlib.h>

volatile int nondet;
int *keep, *weak, x;

/* The value of s changes only after the widening delay, from a singleton:
   the widening returns its second argument, and the memory map then visits
   every binding common to both states. */
void shift(void) {
  int a = 0, b = 0, s = 0;
  while (nondet) {
    s = b;
    b = a;
    a = 1;
  }
  x = s;
}

/* Converges before the widening delay. */
void quiet(void) {
  int s = 0;
  while (nondet)
    s = 1;
  x = s;
}

/* Same loop as shift, writing to a weak allocated block whose maximal
   validity is below its bound: the widening increases it. */
void fill(void) {
  int a = 0, b = 0;
  while (nondet) {
    weak[0] = b;
    b = a;
    a = 1;
  }
}

int main(void) {
  shift();
  keep = malloc(sizeof *keep);
  if (!keep)
    return 1;
  *keep = 1;
  shift();
  quiet();
  for (int j = 0; j < 2; j++) {
    weak = malloc(4 * sizeof *weak);
    if (!weak)
      return 1;
  }
  weak[0] = 0;
  fill();
  return 0;
}
