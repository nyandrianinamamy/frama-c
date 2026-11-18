/* Bodies refused for an allocated block or for an allocation effect. */

#include <stdlib.h>
#include <alloca.h>

int *p, *q, x;

void copy(void) {
  q = p;
}

void logic_only(void) {
  /*@ assert p != \null; */
  x = 1;
}

void allocate(void) {
  p = malloc(sizeof *p);
}

void resize(void) {
  p = realloc(p, 2 * sizeof *p);
}

void release(void) {
  free(p);
}

void scratch(void) {
  char *s = alloca(4);
  s[0] = 1;
}

/* The second call, from the same call site, does not reach alloca. The
   block allocated by the first call is registered for the same callstack
   and is freed again at the return. */
void scratch_once(int c) {
  if (c) {
    char *s = alloca(4);
    s[0] = 1;
  }
}

void vla(int n) {
  int a[n];
  a[0] = 1;
  x = a[0];
}

int main(void) {
  allocate();
  if (!p)
    return 1;
  copy();
  logic_only();
  resize();
  if (!p)
    return 1;
  release();
  scratch();
  for (int i = 0; i < 2; i++)
    scratch_once(i == 0);
  vla(3);
  return 0;
}
