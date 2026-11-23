/* run.config
   MODULE: hit_log_observer @PTEST_NAME@
   STDOPT: +"-eva-no-alloc-returns-null -main cond_main"
   STDOPT: +"-eva-no-alloc-returns-null -main weak_main"
   STDOPT: +"-eva-no-alloc-returns-null -main two_main"
   STDOPT: +"-eva-no-alloc-returns-null -main again_main -eva-slevel 10"
   STDOPT: +"-eva-no-alloc-returns-null -main admit_main -eva-slevel 10"
   STDOPT: +"-eva-no-alloc-returns-null -main calloc_main -eva-slevel 10"
   STDOPT: +"-eva-no-alloc-returns-null -main widen_main -eva-widening-delay 1"
   STDOPT: +"-eva-no-alloc-returns-null -main two_states_main -eva-slevel 10"
   STDOPT: +"-eva-no-alloc-returns-null -main leak_main"
   STDOPT: +"-eva-no-alloc-returns-null -main sweep_main -eva-slevel 10"
   STDOPT: +"-eva-no-alloc-returns-null -main cond_sweep_main -eva-slevel 10"
*/

/* #122: the heap calls analysed by their body are answered by the rule,
   with the blocks that their heap effects cover, the removal mask and the
   sweep map, instead of their full states. Each run is compared by the
   observer with the run without memexec. heap_rule.ml prints, at each
   labelled statement of each heap call, the allocated blocks that the Inner
   part covers, those of them that it does not bind (the removal mask), and
   the blocks swept on every path and on some path. For the calls of release
   and crelease, it also applies the cache entry of one call to the
   body-entry state of another call, which differs from it only in a block
   that the body does not touch, and compares the answer with the answer of
   that call. */

#include <stdlib.h>
#include "__fc_builtin.h"
char *g, *h, *spare; int z;

/* A conditional free: the block of q is freed on some path. */
void cf(char *p, int c) { if (c) free(p); L1: z = 1; }
void cond_main(void) {
  char *q = malloc(4); q[0] = 7; g = q; h = q;
  cf(q, Frama_C_interval(0, 1)); M1: ;
}

/* A weak free: the block is weak, the free joins the swept values with the
   others, and the block stays. */
void wf(char *p) { free(p); L2: ; }
void weak_main(void) {
  /*@ eva_allocate fresh_weak; */
  char *q = malloc(4);
  q[0] = 7; g = q;
  wf(q); M2: ;
}

/* A free with two targets: both blocks stay, and the pointers to each of
   them are joined with escaping addresses. */
void tf(char *p) { free(p); L3: ; }
void two_main(void) {
  char *a = malloc(4); char *b = malloc(4);
  a[0] = 1; b[0] = 2; g = a; h = b;
  tf(Frama_C_interval(0, 1) ? a : b); M3: ;
}

/* A block freed and allocated again within the call. The first call of
   again creates the block; the second frees it, then malloc reuses it, absent
   from the state. h points to it at the second call. */
void again(void) { free(g); g = malloc(4); *g = 2; L4: ; }
void again_main(void) {
  for (int i = 0; i < 2; i++) { again(); h = g; }
  M4: ;
}

/* A weak block reused at a size that its record already admits. The first
   call creates the block, of 8 bytes, which admit_main initializes. The
   second reuses it while it exists: it becomes weak, of 4 to 8 bytes. The
   third reuses it at 8 bytes: its record does not change, but its 8 bytes
   may be uninitialized again. */
void rw(int n) { g = malloc(n); L5: ; }
void admit_main(void) {
  for (int i = 0; i < 3; i++) {
    rw(i == 1 ? 4 : 8);
    if (i == 0) { int *q = (int *)g; q[0] = 1; q[1] = 2; }
  }
  M5: ;
}

/* calloc on a reused block: the second call reuses the block of the first
   one while it exists, makes it weak, and joins its contents with zeroes. */
void cr(void) { g = calloc(4, 1); L6: ; }
void calloc_main(void) {
  for (int i = 0; i < 2; i++) { cr(); g[0] = 5; }
  M6: ;
}

/* A validity record raised by the widening of a loop, in a call that did
   not allocate the block. */
void wl(int *p) { while (Frama_C_interval(0, 1)) *p = 7; L7: ; }
void widen_main(void) {
  /*@ eva_allocate fresh_weak; */
  int *p = malloc(sizeof(int));
  wl(p); M7: ;
}

/* One allocation evaluated in two states: the first evaluation creates the
   block, the second reuses it, absent from its state. */
void two(int c) { if (c) z = 1; else z = 2; g = malloc(4); L8: ; }
void two_states_main(void) { two(Frama_C_interval(0, 1)); M8: ; }

/* Frama_C_check_leak reads every allocated block of the state: the heap
   calls that call it keep their full states. */
/*@ assigns \nothing; */
void Frama_C_check_leak(void);
void leak(void) { char *p = malloc(4); p[0] = 1; Frama_C_check_leak(); L9: ; }
void leak_main(void) { leak(); M9: ; }

/* The two calls of release, and the two calls of crelease, come from one
   call site, in two states of their caller that differ in spare only: with
   spare = 0, and with spare pointing to the block that the call frees. In
   the first call, spare is outside the blocks that the Inner part covers. */
void release(void) { free(g); R: ; }
void sweep_main(void) {
  int k = Frama_C_interval(0, 1);
  g = malloc(4);
  if (k) spare = g;
  release();
  S: ;
}

void crelease(int c) { if (c) free(g); CR: ; }
void cond_sweep_main(void) {
  int k = Frama_C_interval(0, 1);
  g = malloc(4);
  if (k) spare = g;
  crelease(Frama_C_interval(0, 1));
  CS: ;
}
