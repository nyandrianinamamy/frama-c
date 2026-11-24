/* run.config
   MODULE: hit_log_observer @PTEST_NAME@
   STDOPT: +"-eva-no-alloc-returns-null -main alloc_main -cpp-extra-args=-DWARM"
   STDOPT: +"-eva-no-alloc-returns-null -main alloc_main"
   STDOPT: +"-eva-no-alloc-returns-null -main free_main -cpp-extra-args=-DWARM"
   STDOPT: +"-eva-no-alloc-returns-null -main free_main"
   STDOPT: +"-eva-no-alloc-returns-null -main chain_main"
   STDOPT: +"-eva-no-alloc-returns-null -main pair_main"
   STDOPT: +"-eva-no-alloc-returns-null -main loop_main -eva-slevel 20"
   STDOPT: +"-eva-no-alloc-returns-null -main frames_main"
   STDOPT: +"-eva-no-alloc-returns-null -main rec_main -eva-unroll-recursive-calls 5"
   STDOPT: +"-main alloc_main -cpp-extra-args=-DWARM"
   STDOPT: +"-main pair_main"
   STDOPT: +"-eva-no-alloc-returns-null -main stop_main -cpp-extra-args=-DWARM"
   STDOPT: +"-eva-no-alloc-returns-null -main stop_main"
*/

/* #128: a hit on the entry of a heap call passes the heap effects of the
   entry, through its renaming, to the call that makes it, as an analysed
   call does. The call that makes the hit is then stored by memexec like a
   call whose child was analysed, and can itself be a hit.
   Each run is compared by the observer with the run without memexec. The
   device heap_upward.ml prints, for each call of a function of this file
   whose name does not end with _main, the outputs that the inout plugin
   gives for it, and for each of these calls analysed by its body, its heap
   effects, whether memexec stores it and its key, and the blocks that its
   entry covers before its labelled statements. Allocated blocks are named by
   their stack and rank, so that the runs with and without WARM, whose
   callstacks are the same, print the same lines for the same call.
   As in heap_hit.c, the pointer to the block that a call frees is kept in
   the global cur: free reports the cells that its sweep changes as written,
   and the key of the call that frees holds them. */

#include <stdlib.h>
#include "__fc_builtin.h"

int *cur, *keep, *slot;
int mode;

/* Runs 0 and 1: child_mk allocates a block; parent_alloc calls it and reads
   mode, which child_mk does not read. With WARM, the first call of child_mk
   computes its entry: in the first call of parent_alloc, child_mk is a hit,
   and parent_alloc is analysed. Without WARM, child_mk is analysed there.
   The device prints the same effects, key and coverage for this call of
   parent_alloc in both runs. The second call of parent_alloc, on another
   callstack, is a hit of the entry of the first, with child_mk below it. */
int *child_mk(int v) { int *p = malloc(sizeof(int)); *p = v; K: return p; }

int *parent_alloc(int v) { int *q = child_mk(v); *q += mode; P: return q; }

void alloc_main(void) {
#ifdef WARM
  int *w = child_mk(1);
#endif
  int *a = parent_alloc(1);
  int *b = parent_alloc(1);
  Z: ;
}

/* Runs 2 and 3: child_rel frees the block of cur. With WARM, its first call
   computes its entry while keep does not point to the block: keep is not
   in its key. In the first call of parent_free, keep points to the block,
   child_rel is a hit, and it sweeps keep, a cell of its frame. The outputs
   of the hit hold keep, as those of child_rel analysed there without WARM:
   the key of parent_free holds keep in both runs. The second call of
   parent_free is a hit. */
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

/* Run 4: a free three calls down. The first call of outer computes the
   entries of leaf, mid, top and outer. At the second call of outer, k
   differs: leaf is a hit and sweeps keep, while mid, top and outer are
   analysed and stored. The third call of outer is a hit of the entry of the
   second, with the free three calls below the hit. The call of mid from
   chain_main is then a hit of the entry of mid made below the second call
   of outer, with the free two calls down. */
void leaf(void) { free(cur); F: ; }
void mid(int k) { leaf(); G: ; }
void top(int k) { mid(k); H: ; }
void outer(int k) { top(k); O: ; }

void chain_main(void) {
  cur = malloc(sizeof(int)); *cur = 3;
  outer(0);
  cur = malloc(sizeof(int)); *cur = 3;
  keep = cur;
  outer(1);
  cur = malloc(sizeof(int)); *cur = 3;
  keep = cur;
  outer(1);
  cur = malloc(sizeof(int)); *cur = 3;
  keep = cur;
  mid(1);
  Z: ;
}

/* Run 5: a parent with two children that are hits: child_mk creates a
   block, drop frees it. The first calls compute their entries. In the
   first call of pair, both are hits: pair receives the creation and the
   removal of the same block. The second call of pair is a hit. */
void drop(void) { free(slot); D: ; }
void pair(int v) { slot = child_mk(v); drop(); Y: ; }

void pair_main(void) {
  slot = child_mk(4);
  drop();
  pair(4);
  pair(4);
  Z: ;
}

/* Run 6: a child hit inside a loop of the parent. Each iteration of
   repeat calls child_mk and frees the block it returns: the third call of
   child_mk is a hit, as #127 predicts for a block freed in each iteration.
   The second call of repeat is a hit, which replays the three allocations
   of the first. */
void repeat(void) {
  for (int i = 0; i < 3; i++) { int *q = child_mk(7); free(q); }
  L: ;
}

void loop_main(void) {
  repeat();
  repeat();
  Z: ;
}

/* Run 7: the child hit sweeps cells of the frame of its parent and of its
   grandparent. The first call of frel computes its entry, where no other
   cell points to the block. In fgrand(0), gk and pk point to the block of
   cur when frel is a hit: it sweeps pk, a local of fparent, and gk, a local
   of fgrand. In fgrand(1), fparent is a hit of the entry of fparent made in
   fgrand(0), whose key holds gk. The last call of fgrand is a hit. */
void frel(void) { free(cur); E: ; }
void fparent(void) { int *pk = cur; frel(); FP: ; }
void fgrand(int k) {
  cur = malloc(sizeof(int)); *cur = 1;
  int *gk = cur;
  fparent();
  FG: ;
}

void frames_main(void) {
  cur = malloc(sizeof(int)); *cur = 1;
  frel();
  fgrand(0);
  fgrand(1);
  fgrand(1);
  Z: ;
}

/* Run 8: recursion. rec_rel frees the block of cur at the bottom of its
   recursion; its recursive calls are analysed by their body. The first call
   computes its entries; in the first call of rec_parent, rec_rel is a hit,
   and the second call of rec_parent is a hit. */
void rec_rel(int n) { if (n) rec_rel(n - 1); else free(cur); RR: ; }
void rec_parent(int k) { rec_rel(1); RP: ; }

void rec_main(void) {
  cur = malloc(sizeof(int)); *cur = 1;
  rec_rel(1);
  cur = malloc(sizeof(int)); *cur = 1;
  keep = cur;
  rec_parent(0);
  cur = malloc(sizeof(int)); *cur = 1;
  keep = cur;
  rec_parent(0);
  Z: ;
}

/* Runs 9 and 10: runs 0 and 5 with the default option
   -eva-alloc-returns-null: malloc also returns a null pointer, on which the
   write that follows stops. */

/* Runs 11 and 12: child_stop frees the block of cur when k is not zero,
   then reads the freed block: the analysis stops on this path, which does
   not return. The sweep of the block is not in the exit of the entry of
   child_stop. A call of child_stop analysed by its body reports keep, which
   points to the block, as written on some path, and not on the paths that
   return. With WARM, the first call of child_stop computes its entry while
   keep does not point to the block: keep is not in its key, and child_stop
   is a hit in the first call of parent_stop. */
void child_stop(int k) { if (k) { free(cur); k = *cur; } S: ; }
void parent_stop(int k) { child_stop(k); T: ; }

void stop_main(void) {
  int k = Frama_C_interval(0, 1);
#ifdef WARM
  cur = malloc(sizeof(int)); *cur = 6;
  child_stop(k);
#endif
  cur = malloc(sizeof(int)); *cur = 6;
  keep = cur;
  parent_stop(k);
  cur = malloc(sizeof(int)); *cur = 6;
  keep = cur;
  parent_stop(k);
  Z: ;
}
