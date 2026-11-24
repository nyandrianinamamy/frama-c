/* run.config
   PLUGIN: eva,inout,from
   MODULE: heap_upward
   STDOPT: +"-eva-no-alloc-returns-null -main free_main -calldeps -cpp-extra-args=-DWARM"
   STDOPT: +"-eva-no-alloc-returns-null -main free_main -calldeps"
*/

/* #128: the cells that the reuse of a call that frees changes by its
   sweeps, outside the cells of its entry, as the from plugin reports them
   for the hit (option -calldeps). The from plugin runs the analysis before
   the observer of the hit log could: these runs load only the device
   heap_upward.ml, which prints the inputs and outputs of each call of a
   function of this file whose name does not end with _main, as in
   heap_upward.c. The program is that of runs 2 and 3 of heap_upward.c,
   which the observer compares with the run without memexec; the runs with
   and without WARM have the same callstacks.

   With WARM, the call of child_rel in the first call of parent_free is a
   hit that sweeps keep, a cell outside its entry: the from plugin gives
   keep from nothing for this call, as for the call of child_rel analysed
   there without WARM. */

#include <stdlib.h>

int *cur, *keep;

void child_rel(void) { free(cur); R: ; }
void parent_free(void) { child_rel(); Q: ; }

void free_main(void) {
#ifdef WARM
  cur = malloc(sizeof(int)); *cur = 2;
  child_rel();
#endif
  cur = malloc(sizeof(int)); *cur = 2;
  keep = cur;
  parent_free();
  cur = malloc(sizeof(int)); *cur = 2;
  keep = cur;
  parent_free();
  Z: ;
}
