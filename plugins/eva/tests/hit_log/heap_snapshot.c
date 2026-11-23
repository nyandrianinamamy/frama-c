/* run.config
   MODULE: @PTEST_NAME@
   STDOPT: +"-eva-no-alloc-returns-null -main snap_main -eva-slevel 10 -eva-slevel-function widen:0 -eva-widening-delay 1 -eva"
*/

/* #126: the snapshot of the allocated blocks at the start of a call, as
   memexec rebuilds it from the blocks at the end of the call and from the
   validity mutations that the call received. heap_snapshot.ml takes the
   snapshot at the start of each call analysed by its body, rebuilds it when
   the call ends, and prints the blocks where the two differ, and, as a
   control, the blocks whose snapshot at the end differs from the one taken
   at the start. Memexec stores no call that received a validity mutation:
   this checks the rebuilding on the calls that do. */

#include <stdlib.h>
#include "__fc_builtin.h"

char *g;
int *w;

/* The three calls of m come from one call site, through outer, so the
   policy by_stack keeps one list of blocks for them. The first call creates
   a block, which grow_main frees. The second reuses it, absent, and resizes
   it. The third reuses it while it exists, resizes it again, and makes it
   weak: the validity record, the type and the strength of a block of the
   start states of outer and m change. */
void m(int n) { g = malloc(n); }
void outer(int n) { m(n); }

void grow_main(void) {
  for (int i = 0; i < 3; i++) {
    outer(4 * (i + 1));
    if (i == 0) free(g);
  }
}

/* The widening of the loop raises the validity record of the weak block of
   w, a block of the start state of widen. */
void widen(void) {
  while (Frama_C_interval(0, 1)) *w = 7;
}

/* rel removes the block of its start state that it frees, which changes no
   field of its snapshot. */
void rel(char *p) { free(p); }

void snap_main(void) {
  grow_main();
  /*@ eva_allocate fresh_weak; */
  w = malloc(sizeof(int));
  widen();
  rel(g);
}
