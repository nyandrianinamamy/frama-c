/* run.config
   STDOPT: +"-eva-no-alloc-returns-null -main local_main"
   STDOPT: +"-eva-no-alloc-returns-null -main below_main"
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
