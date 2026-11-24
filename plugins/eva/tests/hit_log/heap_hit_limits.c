/* run.config
   STDOPT: +"-eva-no-alloc-returns-null -main local_main"
   STDOPT: +"-eva-no-alloc-returns-null -main below_main"
   STDOPT: +"-eva-no-alloc-returns-null -main split_main -eva-slevel 10"
*/

/* #126: the limits of the reuse of the calls that free. Each run is
   compared by the observer with the run without memexec. */

#include <stdlib.h>

/* Run 0: the pointers to the freed blocks are in locals of the caller.
   free reports the cells that its sweep changes as written: the first call
   of rel sweeps a, which is thus in its key. At the second call, a is an
   escaping address, and the call is analysed, as without -eva-hit-log. */
void rel(int *p) { free(p); }

void local_main(void) {
  int *a = malloc(sizeof(int));
  int *b = malloc(sizeof(int));
  *a = 5; *b = 5;
  rel(a);
  rel(b);
}

/* Run 1: move frees a block and allocates under the policy imprecise,
   whose single block exists from the second call on: the builtin lets
   memexec store the call, and the hit log refuses it, as it allocates, and
   pmove with it. The third call of pmove has the input state of the second:
   memexec would have reused it, and the call of move made during its
   analysis would have been below the hit. */
int *src, *dst;
void move(void) {
  free(src);
  /*@ eva_allocate imprecise; */
  dst = malloc(sizeof(int));
}
void pmove(void) { move(); }

void below_main(void) {
  for (int i = 0; i < 3; i++) {
    src = malloc(sizeof(int));
    *src = 2;
    pmove();
  }
}

/* Run 2: srel frees its argument on one of two paths, and its two returns
   are kept apart by the split on k. The sweep map of the stored call is
   that of its return for all its states: the block is swept on some path.
   On a hit, the state that returns 1 no longer binds the block, and the
   pointer kept in the frame is swept exactly; in the state that returns 0
   the block is bound, and kept is joined with an escaping address, where
   the run without memexec leaves it valid. The answers on that branch
   cover those of the reference, and the read of *kept gets an alarm that
   the reference does not have. */
int *scur, *kept, sd, sseen;
volatile int choice;
int srel(int *p) {
  int k = !!choice;
  /*@ split k; */
  if (k) free(p);
  return k;
}

void split_main(void) {
  scur = malloc(sizeof(int));
  *scur = 8;
  srel(scur);
  scur = malloc(sizeof(int));
  *scur = 8;
  kept = scur;
  if (srel(scur))
    sseen = kept == &sd;
  else
    sseen = *kept;
}
