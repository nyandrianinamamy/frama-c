/* run.config
   MODULE: hit_log_observer heap_alloc heap_names
   STDOPT: +"-eva-no-alloc-returns-null -main direct_main"
   STDOPT: +"-eva-no-alloc-returns-null -main escape_main"
   STDOPT: +"-eva-no-alloc-returns-null -main store_main"
   STDOPT: +"-eva-no-alloc-returns-null -main loop_main -eva-slevel 10"
   STDOPT: +"-eva-no-alloc-returns-null -main loop_main -eva-slevel 10 -eva-mlevel 1"
   STDOPT: +"-eva-no-alloc-returns-null -main loop_main -eva-slevel 10 -eva-mlevel 2"
   STDOPT: +"-eva-no-alloc-returns-null -main iter_main -eva-slevel 10"
   STDOPT: +"-eva-no-alloc-returns-null -main two_main"
   STDOPT: +"-eva-no-alloc-returns-null -main parent_main"
   STDOPT: +"-eva-no-alloc-returns-null -main holder_main"
   STDOPT: +"-eva-no-alloc-returns-null -main rec_main -eva-unroll-recursive-calls 5"
   STDOPT: +"-main two_main"
   STDOPT: +"-main escape_main"
*/

/* #130: the reuse of a call that allocates with alloca under the policy
   by_stack. The block is owned by the call of the function that calls
   alloca, and released at the end of that call, in its caller. A hit
   replays the creation of the block and registers it for the callstack of
   the hit; the automatic release at the end of the hit releases it, as at
   the end of an analysed call. heap_alloc.ml prints the tables of the
   allocated blocks after each analysis, heap_names.ml the names of the
   blocks of the policy by_stack, and whether those of the analysis with
   -eva-hit-log are those of the run without memexec. */

#include <alloca.h>
#include <stdlib.h>
#include "__fc_builtin.h"

int x;
int *gp;

/* Run 0: use makes a block with alloca, writes and reads it, and is called
   from two call sites with the same input: the second call is a hit on
   another callstack, and the block of the hit is released when the hit
   ends. */
int use(int n) {
  int *p = alloca(n * sizeof(int));
  p[0] = n;
  p[n - 1] = 2 * n;
  return p[0] + p[n - 1];
}

void direct_main(void) {
  int a = use(2);
  int b = use(2);
 Released: x = a + b;
}

/* Runs 1 and 12: ret returns a pointer to its alloca block. After each
   call, the caller holds an escaping address; reading through it is an
   alarm, which ends the run. Run 12 is run 1 with the default
   -eva-alloc-returns-null. */
int *ret(int n) {
  int *p = alloca(sizeof(int));
  *p = n;
  return p;
}

void escape_main(void) {
  int *a = ret(1);
  int *b = ret(1);
 Escaping: x = *b;
}

/* Run 2: the pointer to the alloca block is stored in a global, in a cell
   of the caller through an argument, and in a block of malloc. Each of these
   cells holds an escaping address after the call. The cells are reset
   before each call, so that the second call of each pair is a hit. */
void to_global(int n) {
  int *p = alloca(sizeof(int));
  *p = n;
  gp = p;
}

void to_cell(int **cell, int n) {
  int *p = alloca(sizeof(int));
  *p = n;
  *cell = p;
}

void store_main(void) {
  int *c;
  int **m = malloc(sizeof *m);
  gp = 0;
  to_global(1);
  gp = 0;
  to_global(1);
  c = 0;
  to_cell(&c, 1);
  c = 0;
  to_cell(&c, 1);
  *m = 0;
  to_cell(m, 1);
  *m = 0;
  to_cell(m, 1);
 Escaping: x = Frama_C_interval(0, 2);
  if (x == 0) x = *gp;
  else if (x == 1) x = *c;
  else x = **m;
}

/* Runs 3 to 5: alloca in a loop, unrolled by slevel, with -eva-mlevel 0, 1
   and 2. Each iteration allocates while the blocks of the earlier
   iterations are alive: the policy makes mlevel + 1 blocks, then reuses the
   last one and makes it weak. The second call of lp is a hit on another
   callstack. */
int lp(int n) {
  int s = 0;
  for (int i = 0; i < n; i++) {
    int *p = alloca(sizeof(int));
    *p = i;
    s += *p;
  }
  return s;
}

void loop_main(void) {
  x = lp(4);
  x = lp(4);
}

/* Run 6: use called from one call site in a loop, unrolled by slevel. The
   block of each call is released at its end, and the policy reuses it,
   absent, at the next call: the second call misses, as its candidate list
   is longer than in the first, and the third and fourth calls are hits. */
void iter_main(void) {
  for (int i = 0; i < 4; i++) x = use(2);
}

/* Runs 7 and 11: two blocks of alloca and one of malloc in one call. The
   blocks of alloca are released at the end of the call, the block of
   malloc survives it. Run 11 is run 7 with the default
   -eva-alloc-returns-null. */
int *two(int n) {
  int *p = alloca(sizeof(int));
  int *q = alloca(2 * sizeof(int));
  int *m = malloc(sizeof(int));
  *p = n;
  q[1] = n + 1;
  if (m) *m = *p + q[1];
  return m;
}

void two_main(void) {
  int *a = two(1);
  int *b = two(1);
  if (a && b) x = *a + *b;
  free(a);
  free(b);
}

/* Run 8: child, which calls alloca, is called twice by parent: the second
   call is a hit, and its block is released at its end, inside parent.
   parent is then a hit on another callstack: the blocks of its two calls of
   child are created and released as in its analysed call. */
int child(int n) {
  int *p = alloca(sizeof(int));
  *p = n;
  return *p;
}

int parent(int n) {
  int a = child(n);
  int b = child(n);
  return a + b;
}

void parent_main(void) {
  x = parent(1);
  x = parent(1);
}

/* Run 9: holder keeps its block of alloca alive while it calls fill, which
   makes and releases a block of alloca of its own. The second call of fill
   is a hit, on the second block of holder: its end releases the block of
   fill only, and the block of holder is read after it. */
void fill(int *p, int n) {
  int *t = alloca(sizeof(int));
  *t = n;
  *p = *t;
}

int holder(int n) {
  int *p = alloca(sizeof(int));
  int *q = alloca(sizeof(int));
  fill(p, n);
  fill(q, n);
  return *p + *q;
}

void holder_main(void) {
  x = holder(1);
}

/* Run 10: a recursive function that calls alloca at each level, analysed
   with -eva-unroll-recursive-calls. Each level releases its own block. */
int rec(int n) {
  int *p = alloca(sizeof(int));
  *p = n;
  if (n > 0) return *p + rec(n - 1);
  return *p;
}

void rec_main(void) {
  x = rec(2);
  x = rec(2);
}
