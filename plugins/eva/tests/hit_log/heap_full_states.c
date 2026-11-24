/* run.config
   STDOPT: +"-eva-no-alloc-returns-null -main full_main"
*/

/* #128: heap calls whose entry holds full states outside the refusals of
   #120, which are the threaded mode and Frama_C_check_leak. child frees
   the block of its argument and, on some path, calls myst, whose assigns
   clause has a dependency that the inout plugin cannot interpret: the
   footprint of child is unknown after this call, and so is the footprint
   of wrap after its call of child. The hit log keeps full states for both,
   as for a heap call whose footprint is unknown at one of its points, and
   memexec stores neither: the second call of wrap is analysed, and so is
   child below it. The run is compared by the observer with the run
   without memexec. */

#include <stdlib.h>

int arr[2], g, *cur, *keep;
volatile int n;

/*@ axiomatic U { logic integer unknown{L} reads g; } */
/*@ assigns g \from arr[unknown]; */
extern void myst(void);

void child(int *p) { if (n) { myst(); g++; } free(p); C: ; }
void wrap(int *p) { child(p); W: ; }

void full_main(void) {
  cur = malloc(sizeof(int));
  wrap(cur);
  cur = malloc(sizeof(int));
  keep = cur;
  wrap(cur);
  Z: ;
}
