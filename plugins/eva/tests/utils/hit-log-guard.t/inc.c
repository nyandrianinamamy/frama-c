/* A program of the tests of Eva that includes linked.h, a symbolic link
   that run.t makes to a header outside the tests. */

#include "linked.h"

int main(void) {
  from_outside = 1;
  return from_outside;
}
