/* A release in a callee: memexec stores and reuses the call to release, the
   collector refuses it. */

#include <stdlib.h>

static int *owner;

static void release(void) {
  free(owner);
  owner = NULL;
}

int main(void) {
  for (int i = 0; i < 2; ++i) {
    owner = malloc(sizeof *owner);
    if (!owner)
      return 0;
    *owner = 17;
    release();
  }
  return 0;
}
