/* run.config
   MODULE: hit_log_observer heap_alloc heap_names
   STDOPT: +"-eva-no-alloc-returns-null -main create_main"
   STDOPT: +"-eva-no-alloc-returns-null -main freed_main -eva-slevel 20"
   STDOPT: +"-eva-no-alloc-returns-null -main live_main -eva-slevel 20"
   STDOPT: +"-eva-no-alloc-returns-null -main overflow_main"
   STDOPT: +"-eva-no-alloc-returns-null -main maybe_main"
   STDOPT: +"-main create_main"
*/

/* #129: the reuse of a call that allocates with calloc under the policy
   by_stack. A hit replays the decision of the policy, and names the block
   it creates as calloc does; the zeroes that calloc writes in the block are
   in the states of the call that memexec stored. heap_alloc.ml prints the
   tables of the allocated blocks after each analysis, heap_names.ml the
   names of the blocks of the policy by_stack, and whether those of the
   analysis with -eva-hit-log are those of the run without memexec. */

#include <stdlib.h>
#include "__fc_builtin.h"

int *g;
int x;

/* Runs 0 and 5: a call that creates a block, called from two call sites
   with the same input: the second call is a hit on another callstack.
   Run 5 is run 0 with the default -eva-alloc-returns-null. */
int *mkc(int n) {
  int *p = calloc(n, sizeof *p);
  return p;
}

void create_main(void) {
  int *a = mkc(2);
  int *b = mkc(2);
  if (b) {
    x = b[1];
    /*@ assert zero: x == 0; */
  }
}

/* Runs 1 and 2: calls of cz from one call site in a loop, unrolled by
   slevel. The policy reuses the block of the first iteration. In run 1, the
   block is freed in each iteration: the second call reuses it, absent, and
   misses, as its candidate list is longer than in the first; the third
   call is a hit. In run 2, the block is left live: the second call reuses
   it while it exists and makes it weak, the third misses, as the block is
   weak at its start and was strong at the start of the second, and the
   fourth is a hit. */
void cz(int n) {
  g = calloc(n, sizeof *g);
}

void freed_main(void) {
  for (int i = 0; i < 4; i++) {
    cz(1);
    x = *g;
    free(g);
  }
}

void live_main(void) {
  for (int i = 0; i < 5; i++) {
    cz(1);
    x = *g;
  }
}

/* Run 3: a size that always overflows. calloc allocates nothing and
   returns a null pointer; memexec stored this call before #129, and the
   second call is a hit. */
int *big(void) {
  return calloc(0x10000, 0x10001);
}

void overflow_main(void) {
  int *a = big();
  int *b = big();
  x = a == 0 && b == 0;
}

/* Run 4: a size that may overflow. calloc returns the block or a null
   pointer, even with -eva-no-alloc-returns-null. */
int *maybe(unsigned n) {
  int *p = calloc(n, 0x10000);
  if (p) *p = 1;
  return p;
}

void maybe_main(void) {
  unsigned n = Frama_C_unsigned_int_interval(1, 0x20000);
  int *a = maybe(n);
  int *b = maybe(n);
  if (b) x = *b;
}
