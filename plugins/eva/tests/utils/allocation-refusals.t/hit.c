/* A memexec hit runs no body: the caller checks the requires clauses of the
   callee again, with its own recording. */

#include <stdlib.h>

int x, *p;

/*@ requires \valid(p); */
void leaf(void) { x = 1; }

void warm(void) { leaf(); }

void hit_only(void) { leaf(); }

int main(void) {
  p = malloc(sizeof *p);
  if (!p)
    return 1;
  warm();
  hit_only();
  return x;
}
