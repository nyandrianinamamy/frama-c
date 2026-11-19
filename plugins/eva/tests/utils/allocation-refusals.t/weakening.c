/* A block becomes weak at its second allocation from the same call stack.
   After that, a body whose analysis compares several states through the
   partitioning index is refused, though it does not access the block. */

#include <stdlib.h>

volatile int nondet;
int *p, x;

void alloc(void) { p = malloc(sizeof *p); }

/* Two states reach the end of the body. */
void branch(void) {
  if (nondet)
    x = 1;
  else
    x = 2;
}

/* One state at each point. */
void straight(void) { x = 3; }

int main(void) {
  branch();
  straight();
  for (int i = 0; i < 3; i++)
    alloc();
  branch();
  straight();
  return 0;
}
