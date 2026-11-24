/* run.config
   MODULE: hit_log_observer @PTEST_NAME@
   STDOPT: +"-eva-no-alloc-returns-null -main cs_main"
   STDOPT: +"-eva-no-alloc-returns-null -main freed_main -eva-slevel 20"
   STDOPT: +"-eva-no-alloc-returns-null -main live_main -eva-slevel 20"
   STDOPT: +"-eva-no-alloc-returns-null -main cand_main -eva-slevel 20"
   STDOPT: +"-eva-no-alloc-returns-null -main recycle_main -eva-slevel 20"
   STDOPT: +"-eva-no-alloc-returns-null -main branch_main -eva-slevel-function branchy:4"
   STDOPT: +"-eva-no-alloc-returns-null -main resize_main -eva-slevel 20"
   STDOPT: +"-eva-no-alloc-returns-null -main after_main -eva-slevel 20"
   STDOPT: +"-eva-no-alloc-returns-null -main nested_main"
*/

/* #127: memexec stores a call that allocates with malloc under the policy
   by_stack, and reuses it on a call whose candidates, the blocks that the
   policy made before the call on the stack of each allocation, correspond
   to those of the stored call. A hit replays the decisions of the policy in
   their order: it creates the blocks that the stored call created, on the
   stack of the hit, and reuses and resizes the blocks it reused. Each run is
   compared by the observer with the run without memexec. heap_alloc.ml
   prints the tables of the allocated blocks after each analysis, and
   whether those of the analysis with -eva-hit-log are those of the run
   without memexec. */

#include <stdlib.h>
#include "__fc_builtin.h"

/* Run 0: an allocating function hits on another callstack. The two calls of
   mk are made from two call sites: the stacks of their allocations differ,
   and neither has a block before the call. The hit creates a block on the
   stack of its own call. */
int *mk(int v) {
  int *p = malloc(sizeof *p);
  *p = v;
  MK: return p;
}

void cs_main(void) {
  int *a = mk(1);
  int *b = mk(1);
  CS: ;
}

/* Runs 1 and 2: a loop on one callstack, unrolled by slevel, in which each
   iteration calls make. The key of make holds no variable of the caller:
   its calls differ only by the blocks that the policy made before them on
   the stack of the allocation, the candidates.
   Run 1: the block is freed in each iteration. Iteration 1 creates it.
   Iteration 2 has it as candidate, absent: a miss, and it reuses the block.
   Iteration 3 has the same candidate, absent, with the same snapshot: a
   hit, as #120 predicts.
   Run 2: the block is left live. Iteration 2 reuses it while it exists, and
   makes it weak. Iteration 3 has it weak where the entry of iteration 2
   recorded it strong: a miss. Iteration 4 has the input of iteration 3: a
   hit, as #120 predicts. */
int *make(void) {
  int *p = malloc(sizeof *p);
  *p = 1;
  MA: return p;
}

void freed_main(void) {
  for (int i = 0; i < 4; i++) {
    int *q = make();
    free(q);
  }
  FM: ;
}

void live_main(void) {
  int *q;
  for (int i = 0; i < 5; i++) q = make();
  LM: ;
}

/* Run 3: a candidate left live by an earlier call, renamed. The calls of
   keep_one in the second loop are made from another call site than those
   of the first loop. In each loop, the first call creates a block, and the
   second one reuses it while it exists, and makes it weak. The second call
   of the second loop has the input of the second call of the first loop,
   up to the renaming of their blocks: a hit, which makes the candidate
   weak. A pointer to the candidate is in the frame of the call, in saved. */
int *last, *saved;
void keep_one(void) {
  last = malloc(sizeof(int));
  *last = 1;
  KO: ;
}

void cand_main(void) {
  for (int i = 0; i < 2; i++) keep_one();
  for (int i = 0; i < 2; i++) { saved = last; keep_one(); }
  CM: ;
}

/* Run 4: a block freed and allocated again within the call. The block of rc
   is freed and the policy reuses it, absent, at the next allocation. The
   second call of each loop frees the block that the first call created and
   reuses it. The second call of the second loop is a hit on the entry of
   the second call of the first loop. Before it, saved points to the block,
   from the frame: the hit sweeps it. */
int *rc;
void recycle(void) {
  free(rc);
  rc = malloc(sizeof(int));
  *rc = 3;
  RC: ;
}

void recycle_main(void) {
  for (int i = 0; i < 2; i++) recycle();
  for (int i = 0; i < 2; i++) { if (i) saved = rc; recycle(); }
  RM: ;
}

/* Run 5: one allocation evaluated in two states of the body. With slevel,
   the two branches of branchy reach the allocation in two states: the
   policy creates a block in the first, and reuses it, absent from the
   second, in the second. The block stays strong. The second call is a hit,
   on another callstack. */
int *branchy(int c) {
  int x;
  if (c) x = 1; else x = 2;
  int *p = malloc(sizeof *p);
  *p = x;
  BR: return p;
}

void branch_main(void) {
  int *a = branchy(Frama_C_interval(0, 1));
  int *b = branchy(Frama_C_interval(0, 1));
  BM: ;
}

/* Run 6: a resize on a hit. The first call of grow in each loop creates a
   block of 4 bytes, of type char[4]; the second one reuses it, absent, for
   8 bytes: the builtin resizes it, and changes its type to char[]. The
   second call of the second loop is a hit on the entry of the second call
   of the first loop: the replay resizes the block through the builtin.
   The snapshot of the block at the start of the stored call, 4 bytes and
   char[4], is not the one at its end. */
char *rs;
void grow(int n) {
  rs = malloc(n);
  *rs = 1;
  GR: ;
}

void resize_main(void) {
  for (int i = 0; i < 2; i++) { grow(4 * (i + 1)); free(rs); }
  for (int i = 0; i < 2; i++) { grow(4 * (i + 1)); free(rs); }
  RZ: ;
}

/* Run 7: the tables after a hit. Each loop calls alloc_two from its own
   call site; the first iteration frees the block it gets. In the second
   loop, the first call is a hit that creates a block, which the free reads
   in the table of the allocated blocks; the second call is a hit that
   reuses it, absent. The third call has no entry with its argument and is
   analysed after the hits, on the same callstack: the policy reads the list
   of the stack, which the replay extended, and reuses its block, present,
   which it makes weak. */
int *hold;
int *alloc_two(int v) {
  int *p = malloc(sizeof *p);
  *p = v;
  AT: return p;
}

void after_main(void) {
  for (int i = 0; i < 2; i++) { hold = alloc_two(i); if (i == 0) free(hold); }
  for (int i = 0; i < 3; i++) { hold = alloc_two(i); if (i == 0) free(hold); }
  AM: ;
}

/* Run 8: an allocation two calls down. outer_alloc calls inner_alloc, which
   allocates. The second call of outer_alloc is a hit; inner_alloc is below
   the hit, and its start names the block of the hit. */
int *inner_alloc(int v) {
  int *p = malloc(sizeof *p);
  *p = v;
  IA: return p;
}

int *outer_alloc(int v) {
  int *p = inner_alloc(v);
  OA: return p;
}

void nested_main(void) {
  int *a = outer_alloc(5);
  int *b = outer_alloc(5);
  NM: ;
}
