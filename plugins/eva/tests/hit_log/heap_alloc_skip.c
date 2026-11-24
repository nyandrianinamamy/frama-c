/* run.config
   MODULE: hit_log_observer heap_alloc
   STDOPT: +"-eva-no-alloc-returns-null -main skip_main -eva-mlevel 1 -eva-slevel 20"
*/

/* #127: a candidate that the policy passes over because it exists, and
   that the call does not read or write. With -eva-mlevel 1, the policy
   reuses the first block of the stack that does not exist, and makes the
   second weak if both exist. bare does not read or write the blocks of the
   stack; the key of a stored call holds them as candidates.
   Iteration 0 creates b0, which first keeps; iteration 1 creates b1, and
   frees it. Iteration 2 passes over b0, which exists, and reuses b1; then
   b0 and b1 are freed. Iteration 3 has the same candidates as iteration 2,
   with the same numbers, and the same state except that b0 does not exist:
   the policy reuses b0, and the call misses the entry of iteration 2.
   Iteration 4 is the same call as iteration 3, and hits its entry. Each run
   is compared by the observer with the run without memexec; heap_alloc.ml
   compares the tables of the allocated blocks. */

#include <stdlib.h>

int *first;

int *bare(void) {
  return malloc(sizeof(int));
}

void skip_main(void) {
  for (int i = 0; i < 5; i++) {
    int *p = bare();
    *p = i;
    if (i == 0)
      first = p;
    else {
      free(p);
      if (i == 2)
        free(first);
    }
  }
}
