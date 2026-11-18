/* Automatic blocks are freed by the caller, at the return of the call. */

#include <alloca.h>

int p;

/* The second invocation never returns: its block is not freed again. */
void scratch(int i) {
  if (i == 0) {
    char *a = alloca(4);
    a[0] = 1;
  } else
    while (1) { }
}

int no_return(void) {
  for (int i = 0; i < 2; ++i) {
    scratch(i);
    ++p;
  }
  return p;
}

/* No caller frees the block of the entry point. */
int entry(void) {
  char *q = alloca(1);
  *q = 19;
  return *q;
}
