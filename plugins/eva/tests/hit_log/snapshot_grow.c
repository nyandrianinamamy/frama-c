/* run.config
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main grow_main"
*/

/* #123: the results that memexec keeps for one input state. One site
   allocates 1 byte, then 2, and so on up to 7, then 7 again, and frees the
   block each time: the block stays strong, and each allocation of a new
   size raises its validity record. keep_g has the same argument and key at
   each call; the block is mentioned through its argument. Each call misses
   while the record rises, and the last one hits the result of the call
   before it. The record never comes back to a former value: the results of
   the former calls can never be reused. */

#include <stdlib.h>

int keep_g(char *p) { G: return 7; }

int r_grow[8];
void grow_main(void) {
  for (int i = 0; i < 8; i++) {
    char *p = malloc(i < 7 ? i + 1 : 7);
    r_grow[i] = keep_g(p);
    free(p);
  }
}
