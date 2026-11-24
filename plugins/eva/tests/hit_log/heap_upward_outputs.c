/* run.config
   MODULE: hit_log_observer heap_upward
   STDOPT: +"-eva-no-alloc-returns-null -main split_main -eva-slevel-function child_split:10 -eva-split-return-function child_split:0 -cpp-extra-args=-DWARM"
   STDOPT: +"-eva-no-alloc-returns-null -main split_main -eva-slevel-function child_split:10 -eva-split-return-function child_split:0"
*/

/* #128: the cells that the reuse of a call that frees changes by its
   sweeps, outside the cells of its entry, as the inout plugin reports them
   for the hit, on a call whose returns are kept apart. Each run is
   compared by the observer with the run without memexec, and the device
   heap_upward.ml prints the inputs and outputs of each call of a function
   of this file whose name does not end with _main, as in heap_upward.c.
   The runs with and without WARM have the same callstacks. */

#include <stdlib.h>
#include "__fc_builtin.h"

int *cur, *keep;

/* Runs 0 and 1: child_split frees the block of cur when c is not zero, and
   returns 1 then, 0 otherwise. Options -eva-slevel-function and
   -eva-split-return-function keep its two returns apart, and its callers
   join them. A hit on its entry sweeps the block exactly on the return
   where the block is freed, and as a join on the other. keep, outside the
   entry with WARM, is then written on the paths that return, and not
   surely: the device prints it in the outputs of the hit and not in its
   sure outputs, as for the call analysed without WARM. */
int child_split(int c) {
  if (c) { free(cur); return 1; }
  CS: return 0;
}
void parent_split(int c) { child_split(c); PS: ; }

void split_main(void) {
  int c = Frama_C_interval(0, 1);
#ifdef WARM
  cur = malloc(sizeof(int)); *cur = 9;
  child_split(c);
#endif
  cur = malloc(sizeof(int)); *cur = 9;
  keep = cur;
  parent_split(c);
  cur = malloc(sizeof(int)); *cur = 9;
  keep = cur;
  parent_split(c);
  Z: ;
}
