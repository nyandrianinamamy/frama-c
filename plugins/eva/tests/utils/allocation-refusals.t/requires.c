/* Requires clauses that read an allocated block that the body does not
   access. The clauses are checked at the call site. */

#include <stdlib.h>

int x;

/*@ requires \valid(p); */
void valid_only(int *p) { x = 1; }

/*@ requires \initialized(p); */
void initialized_only(int *p) { x = 2; }

/*@ requires \block_length(p) >= sizeof(int); */
void length_only(int *p) { x = 3; }

int main(void) {
  int *p = malloc(sizeof *p);
  if (!p)
    return 1;
  *p = 0;
  valid_only(p);
  initialized_only(p);
  length_only(p);
  return 0;
}
