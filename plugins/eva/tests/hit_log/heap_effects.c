/* run.config
   MODULE: hit_log_observer @PTEST_NAME@
   STDOPT: +"-eva-no-alloc-returns-null -main malloc_main -eva-slevel 10"
   STDOPT: +"-eva-no-alloc-returns-null -main two_states_main -eva-slevel 10"
   STDOPT: +"-eva-no-alloc-returns-null -main calloc_realloc_main"
   STDOPT: +"-eva-no-alloc-returns-null -main free_main"
   STDOPT: +"-eva-no-alloc-returns-null -main alloca_main"
   STDOPT: +"-eva-no-alloc-returns-null -main vla_main"
   STDOPT: +"-eva-no-alloc-returns-null -main widen_main -eva-widening-delay 1"
   MODULE: @PTEST_NAME@
   OPT: -machdep x86_32 -eva-verbose 0 -eva-no-remove-redundant-alarms -eva-no-alloc-returns-null -main all_main -eva
*/

/* #121: the heap effects, emitted where they happen. heap_effects.ml prints
   the effects that each call of a function with a body received, when the
   call ends, and the number of effects emitted in the run. The last run is
   without -eva-hit-log and without the observer: nothing is emitted. */

#include <stdlib.h>
#include <alloca.h>
#include "__fc_builtin.h"
char *g; int z;

/* The three calls of m come from one call site, so the policy by_stack keeps
   one list of blocks for them. The first call creates a block, which
   malloc_main frees. The second reuses it, absent, and resizes it. The third
   reuses it while it exists, and makes it weak. */
void m(int n) { g = malloc(n); }
void malloc_main(void) {
  for (int i = 0; i < 3; i++) {
    m(4 * (i + 1));
    if (i == 0) free(g);
  }
}

/* One allocation evaluated in two states: the first evaluation creates the
   block, the second reuses it, absent from its state. */
void two(int c) { if (c) z = 1; else z = 2; g = malloc(4); }
void two_states_main(void) { two(Frama_C_interval(0, 1)); }

/* realloc allocates a block, then frees the block of calloc. */
void calloc_realloc_main(void) {
  char *p = calloc(4, 1);
  char *q = realloc(p, 8);
  z = q[0];
}

/* A strong free; a free of a weak block; a free with two targets. */
void strong_free(void) { char *p = malloc(4); free(p); }
void weak_free(void) {
  /*@ eva_allocate fresh_weak; */
  char *p = malloc(4);
  free(p);
}
void two_targets(void) {
  char *a = malloc(4);
  char *b = malloc(4);
  char *p = Frama_C_interval(0, 1) ? a : b;
  free(p);
}
void free_main(void) { strong_free(); weak_free(); two_targets(); }

/* The block of alloca is released at the end of az, in alloca_main. */
void az(void) { char *p = alloca(4); p[0] = 1; z = p[0]; }
void alloca_main(void) { az(); z = 0; }

/* A variable-length array left by the end of its scope, and one left by a
   jump. */
void vla_scope(int n) {
  { char a[n]; a[0] = 1; z = a[0]; }
  z = 0;
}
void vla_jump(int n) {
  {
    char a[n]; a[0] = 1;
    if (n > 2) goto out;
    z = a[0];
  }
 out: z = 0;
}
void vla_main(void) { vla_scope(4); vla_jump(4); }

/* The widening of the loop raises the validity record of the weak block of
   p: the loop initializes the block, and the widening, applied at once, has
   no effect on the state. */
void widen_main(void) {
  /*@ eva_allocate fresh_weak; */
  int *p = malloc(sizeof(int));
  while (Frama_C_interval(0, 1)) *p = 7;
}

void all_main(void) {
  malloc_main();
  two_states_main();
  calloc_realloc_main();
  free_main();
  alloca_main();
  vla_main();
  widen_main();
}
