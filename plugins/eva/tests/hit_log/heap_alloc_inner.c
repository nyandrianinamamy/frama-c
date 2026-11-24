/* run.config
   MODULE: hit_log_observer heap_alloc
   STDOPT: +"-eva-no-alloc-returns-null -main cycle_main -eva-slevel 10"
   STDOPT: +"-eva-no-alloc-returns-null -main twice_main -eva-slevel 10"
*/

/* #127: a block that the stored call creates, then reuses in the same call.
   Each function is called from two call sites with the same input, the
   global that it writes being reset between the calls: the second call is a
   hit on another callstack, and replays the creation, then the reuse of the
   created block. Each run is compared by the observer with the run without
   memexec; heap_alloc.ml compares the tables of the allocated blocks.
   Run 0: cycle allocates, frees, and allocates again on the same stack for
   twice the size: the policy reuses the block it created, absent, and the
   builtin resizes it and changes its type.
   Run 1: twice allocates twice on the same stack without free, at
   -eva-mlevel 0: the policy reuses the block it created, present, and makes
   it weak. */

#include <stdlib.h>

int last;

void cycle(void) {
  for (int i = 0; i < 2; i++) {
    int *t = malloc((i + 1) * sizeof *t);
    *t = i;
    last = *t;
    free(t);
  }
}

void cycle_main(void) {
  cycle();
  last = 0;
  cycle();
}

int *kept;

void twice(void) {
  for (int i = 0; i < 2; i++) {
    int *t = malloc(sizeof *t);
    *t = i;
    kept = t;
  }
}

void twice_main(void) {
  twice();
  kept = 0;
  twice();
}
