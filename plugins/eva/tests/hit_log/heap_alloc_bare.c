/* run.config
   MODULE: hit_log_observer heap_alloc
   STDOPT: +"-eva-no-alloc-returns-null -main bare_main -eva-slevel 20"
*/

/* #127: a call that allocates and does not read or write the block that it
   returns. The loop frees the block after each call, so that from the
   second call on, the policy reuses the block of rank 0 of the stack, which
   does not exist at the start of the call. This block is not among the
   locations that the call reads or writes: it is in the key of the stored
   call as a candidate, and its state at the end of the call, where it
   exists, is copied on a hit. Each run is compared by the observer with the
   run without memexec; heap_alloc.ml compares the tables of the allocated
   blocks. */

#include <stdlib.h>

int *bare(void) {
  return malloc(sizeof(int));
}

void bare_main(void) {
  for (int i = 0; i < 4; i++) {
    int *p = bare();
    *p = i;
    free(p);
  }
}
