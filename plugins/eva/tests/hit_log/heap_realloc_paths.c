/* run.config
   MODULE: hit_log_observer heap_alloc heap_names
   STDOPT: +"-main strong_main -eva-slevel 10 -eva-slevel-function rs:10 -eva-split-return-function rs:0"
   STDOPT: +"-main two_main -eva-slevel-function rs:10 -eva-split-return-function rs:0"
   STDOPT: +"-eva-no-alloc-returns-null -main upward_main"
*/

/* #129: the reuse of a call of realloc whose release of the old block holds
   on some paths only: a realloc that may fail, whose returns are kept
   apart, and a realloc of a pointer with two targets, which frees them
   weakly, below a call that is then a hit. Each run is compared by the
   observer with the run without memexec. heap_alloc.ml prints the tables
   of the allocated blocks after each analysis, heap_names.ml the names of
   the blocks of the policy by_stack. */

#include <stdlib.h>
#include "__fc_builtin.h"

char *g;
int x;

/* realloc of the block of g, to 8 bytes. With the default
   -eva-alloc-returns-null, realloc may fail: it returns a null pointer and
   leaves the block of g live in one state, and frees it in the other. In
   runs 0 and 1, options -eva-slevel-function and -eva-split-return-function
   keep these two returns apart in rs: the entry of rs has an exit where the
   block of g is removed, and an exit where it is live. */
char *rs(void) {
  return realloc(g, 8);
}

/* Run 0: realloc of a strong block. The slevel of strong_main keeps the two
   returns of rs apart in the caller too, so that two states reach each
   later call of rs. Each call site has its own stack for the policy
   by_stack. At the second call site, the first state is a hit on the entry
   of the first call; in the second state, the block that the hit created
   on this stack is absent, and the call misses. At the third call site,
   the content of the block of g differs, and both calls miss. */
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
  g = malloc(4);
  if (!g) return;
  g[0] = 5; g[1] = 2; g[2] = 3; g[3] = 4;
  char *r = rs();
}

/* Run 1: realloc of a pointer with two targets, which frees them weakly,
   with its returns kept apart in rs and joined in two_main. The second
   call is a hit, on two other blocks with the same contents. */
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

/* Run 2: the effects of a hit on rs pass to the call of parent that makes
   it (#128). rs frees two targets weakly: they stay in the state, and are
   in the key of parent only as the blocks that realloc copies. The second
   call of parent is a hit; the third misses, as the content of one of its
   two blocks differs. */
char *parent(void) {
  char *p = rs();
  return p;
}

/* Points g to one of two new blocks, the first byte of the second being
   v. */
void two(char v) {
  char *a = malloc(4);
  char *b = malloc(4);
  a[0] = 1; a[1] = 1; a[2] = 1; a[3] = 1;
  b[0] = v; b[1] = 2; b[2] = 2; b[3] = 2;
  g = Frama_C_interval(0, 1) ? a : b;
}

void upward_main(void) {
  two(2);
  char *p = rs();
  two(2);
  char *q = parent();
  two(2);
  char *r = parent();
  x = r[0];
  two(3);
  char *s = parent();
  x = s[0];
}
