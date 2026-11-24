/* run.config
   MODULE: hit_log_observer heap_alloc heap_names
   STDOPT: +"-eva-no-alloc-returns-null -main strong_main"
   STDOPT: +"-eva-no-alloc-returns-null -main weak_main"
   STDOPT: +"-eva-no-alloc-returns-null -main two_main"
   STDOPT: +"-eva-no-alloc-returns-null -main null_main"
   STDOPT: +"-eva-no-alloc-returns-null -main content_main"
   STDOPT: +"-eva-no-alloc-returns-null -main sizes_main"
   STDOPT: +"-eva-no-alloc-returns-null -main self_main"
   STDOPT: +"-main strong_main"
   STDOPT: +"-main two_main"
   STDOPT: +"-eva-no-alloc-returns-null -main invalid_main"
   STDOPT: +"-eva-no-alloc-returns-null -main calloc_realloc_main"
   STDOPT: +"-eva-no-alloc-returns-null -main upward_main"
   STDOPT: +"-eva-no-alloc-returns-null -main loop_main -eva-slevel 40 -eva-mlevel 0"
   STDOPT: +"-eva-no-alloc-returns-null -main loop_main -eva-slevel 40 -eva-mlevel 1"
   STDOPT: +"-eva-no-alloc-returns-null -main loop_main -eva-slevel 40 -eva-mlevel 2"
   STDOPT: +"-eva-no-alloc-returns-null -main array_main"
*/

/* #129: the reuse of a call that allocates with realloc or reallocarray
   under the policy by_stack. realloc allocates a block, copies the content
   of the blocks its argument points to into it, then frees them. A hit
   replays the decision of the policy and names the block it creates as
   realloc does; the copied content is in the states of the call that
   memexec stored, and the blocks that realloc copies are in the key of the
   call, so that a hit copies the content of the blocks of the hit. The
   release of the old blocks is a removal and a sweep, as for free.
   heap_alloc.ml prints the tables of the allocated blocks after each
   analysis, heap_names.ml the names of the blocks of the policy by_stack,
   and whether those of the analysis with -eva-hit-log are those of the run
   without memexec.

   The callers keep no pointer to an old block in a local variable: free
   reports the cells it sweeps as written, so that such a variable would be
   in the key of the call, and the calls would differ by it (#126). */

#include <stdlib.h>
#include "__fc_builtin.h"

char *g;
int x;

/* realloc of the block of g, to 8 bytes. */
char *rs(void) {
  return realloc(g, 8);
}

/* Runs 0 and 7: realloc of a strong block, freed by realloc, from three call
   sites. The second call is a hit: its block has the content of the block
   of the first call. The third misses: the content of its block differs,
   and the block, which realloc removes, is in the key. Run 7 is run 0 with
   the default -eva-alloc-returns-null: realloc may fail, and frees the
   block on one of its two results only. */
void strong_main(void) {
  g = malloc(4);
  if (!g) return;
  g[0] = 1; g[1] = 2; g[2] = 3; g[3] = 4;
  char *p = rs();
  g = malloc(4);
  if (!g) return;
  g[0] = 1; g[1] = 2; g[2] = 3; g[3] = 4;
  char *q = rs();
  if (!q) return;
  x = q[3];
  /*@ assert copied: x == 4; */
  g = malloc(4);
  if (!g) return;
  g[0] = 5; g[1] = 2; g[2] = 3; g[3] = 4;
  char *r = rs();
}

/* Run 1: realloc of a weak block: realloc copies it and does not remove it.
   The block is not read by the call otherwise; it is in the key because
   realloc copies it. The second call is a hit, the third misses: the
   content of its block differs. */
void weak_main(void) {
  /*@ eva_allocate fresh_weak; */
  g = malloc(4);
  g[0] = 1; g[1] = 2; g[2] = 3; g[3] = 4;
  char *p = rs();
  /*@ eva_allocate fresh_weak; */
  g = malloc(4);
  g[0] = 1; g[1] = 2; g[2] = 3; g[3] = 4;
  char *q = rs();
  x = q[3];
  /*@ eva_allocate fresh_weak; */
  g = malloc(4);
  g[0] = 5; g[1] = 2; g[2] = 3; g[3] = 4;
  char *r = rs();
}

/* Runs 2 and 8: realloc of a pointer with two targets: realloc copies both
   blocks into the new one, and the free is weak. The second call is a hit,
   on two other blocks with the same contents. Run 8 is run 2 with the
   default -eva-alloc-returns-null. */
void two_main(void) {
  char *a = malloc(4);
  char *b = malloc(4);
  if (!a || !b) return;
  a[0] = 1; a[1] = 1; a[2] = 1; a[3] = 1;
  b[0] = 2; b[1] = 2; b[2] = 2; b[3] = 2;
  g = Frama_C_interval(0, 1) ? a : b;
  a = 0; b = 0;
  char *p = rs();
  char *c = malloc(4);
  char *d = malloc(4);
  if (!c || !d) return;
  c[0] = 1; c[1] = 1; c[2] = 1; c[3] = 1;
  d[0] = 2; d[1] = 2; d[2] = 2; d[3] = 2;
  g = Frama_C_interval(0, 1) ? c : d;
  c = 0; d = 0;
  char *q = rs();
  if (!q) return;
  x = q[0];
}

/* Run 3: realloc of a null pointer, which allocates and frees nothing. */
void null_main(void) {
  g = 0;
  char *p = rs();
  char *q = rs();
  q[0] = 1;
}

/* Run 4: the content that realloc copies is that of the block of the hit.
   The block of h holds a pointer to a block whose content is not in the key
   of rh, and differs between the two calls. The second call is a hit; its
   block holds a pointer to the block of the hit, as in the run without
   memexec. */
char **h;

char **rh(void) {
  return realloc(h, 2 * sizeof(char *));
}

void content_main(void) {
  char *x1 = malloc(4);
  x1[0] = 1;
  h = malloc(sizeof(char *));
  *h = x1;
  x1 = 0;
  char **p = rh();
  char *x2 = malloc(4);
  x2[0] = 2;
  h = malloc(sizeof(char *));
  *h = x2;
  x2 = 0;
  char **q = rh();
  x = (*q)[0];
  /*@ assert copied: x == 2; */
}

/* Run 5: realloc of a block of 4 bytes to a larger, a smaller, an equal and
   a zero size, each from two call sites: the second call of each pair is a
   hit. */
char *rz(int n) {
  return realloc(g, n);
}

void fill(void) {
  g[0] = 1; g[1] = 2; g[2] = 3; g[3] = 4;
}

void sizes_main(void) {
  g = malloc(4); fill();
  char *l1 = rz(8);
  g = malloc(4); fill();
  char *l2 = rz(8);
  x = l2[3];
  g = malloc(4); fill();
  char *s1 = rz(2);
  g = malloc(4); fill();
  char *s2 = rz(2);
  x = s2[1];
  g = malloc(4); fill();
  char *e1 = rz(4);
  g = malloc(4); fill();
  char *e2 = rz(4);
  x = e2[3];
  g = malloc(4); fill();
  char *z1 = rz(0);
  g = malloc(4); fill();
  char *z2 = rz(0);
}

/* Run 6: realloc of a block that holds a pointer to itself, copied into the
   new block, then swept by the free of the old block. */
void **s;

void **rself(void) {
  return realloc(s, 2 * sizeof(void *));
}

void self_main(void) {
  s = malloc(sizeof(void *));
  *s = s;
  void **p = rself();
  s = malloc(sizeof(void *));
  *s = s;
  void **q = rself();
  q[1] = q;
}

/* Run 9: realloc of a pointer with a non-zero offset, and of a block that
   was not allocated: realloc returns no state, and its precondition is
   invalid. The calls are stored as before #129. */
char loc[4];

void invalid_main(void) {
  g = malloc(4);
  g = g + 1;
  if (Frama_C_interval(0, 1)) { char *p = rs(); x = 1; }
  if (Frama_C_interval(0, 1)) { char *q = rs(); x = 2; }
  g = loc;
  if (Frama_C_interval(0, 1)) { char *p = rs(); x = 3; }
  if (Frama_C_interval(0, 1)) { char *q = rs(); x = 4; }
}

/* Run 10: calloc, then realloc of its block, in one call: the block of
   calloc is created and freed by the call, and copied into the block of
   realloc. */
char *cr(void) {
  char *p = calloc(4, 1);
  char *q = realloc(p, 8);
  return q;
}

void calloc_realloc_main(void) {
  char *a = cr();
  char *b = cr();
  x = b[0];
  /*@ assert zero: x == 0; */
}

/* Run 11: the effects of a hit on rs pass to the call of parent that makes
   it (#128), which is then itself a hit on another callstack. */
char *parent(void) {
  char *p = rs();
  p[4] = 9;
  return p;
}

void upward_main(void) {
  g = malloc(4); fill();
  char *a = rs();
  g = malloc(4); fill();
  char *b = parent();
  g = malloc(4); fill();
  char *c = parent();
  x = c[4];
}

/* Runs 12 to 14: loops on one callstack, unrolled by slevel, with
   -eva-mlevel 0, 1 and 2. In the first loop, regrow reallocates the block
   of the previous iteration, which realloc frees. In the second, keep
   reallocates a null pointer, which allocates, and the blocks are left
   live. The report gives the iteration of the first hit of each. */
char *k;

void regrow(void) {
  g = realloc(g, 4);
}

void keep(void) {
  k = realloc((void *)0, 4);
  k[0] = 1;
}

void loop_main(void) {
  g = malloc(4);
  g[0] = 1; g[1] = 1; g[2] = 1; g[3] = 1;
  for (int i = 0; i < 8; i++) regrow();
  for (int i = 0; i < 8; i++) keep();
}

/* Run 15: reallocarray, of a block of 4 bytes to 4 elements of 2 bytes,
   from two call sites: the second call is a hit. Then with a size that
   always overflows: reallocarray returns a null pointer and frees nothing,
   and memexec stored this call before #129. The first of these calls sets
   errno to ENOMEM, as the behavior fail of the specification of
   reallocarray says, and errno, which the call writes, is in the key: the
   second call misses and the third is a hit. Then with a size that may
   overflow: reallocarray adds a null result to those of realloc. */
char *ra(unsigned n) {
  return reallocarray(g, n, 2);
}

char *big_ra(void) {
  return reallocarray(g, 0x10000, 0x10001);
}

void array_main(void) {
  g = malloc(4); fill();
  char *p = ra(4);
  g = malloc(4); fill();
  char *q = ra(4);
  x = q[3];
  g = malloc(4); fill();
  char *r = big_ra();
  char *t = big_ra();
  char *w = big_ra();
  unsigned n = Frama_C_unsigned_int_interval(1, 0x90000000);
  g = malloc(4); fill();
  char *u = ra(n);
  g = malloc(4); fill();
  char *v = ra(n);
}
