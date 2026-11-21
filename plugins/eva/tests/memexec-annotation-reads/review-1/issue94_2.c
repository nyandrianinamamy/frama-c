#include <stdlib.h>
static int *owner, *alias;
static void release(void) { free(owner); owner = NULL; }
int main(void) {
  for (int i = 0; i < 3; ++i) {
    owner = malloc(sizeof *owner);
    if (!owner) return 0;
    *owner = 17;
    if (i) alias = owner; else alias = NULL;
    release();
  }
  return 0;
}
