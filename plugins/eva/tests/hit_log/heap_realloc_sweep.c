/* run.config
   MODULE: hit_log_observer heap_alloc heap_names
   STDOPT: +"-eva-no-alloc-returns-null -main strong_main"
   STDOPT: +"-eva-no-alloc-returns-null -main weak_main"
   STDOPT: +"-eva-no-alloc-returns-null -main two_main"
*/

/* #129: the sweep of the pointers to the blocks that realloc releases, on a
   hit, when such a pointer is outside the key of the call. In each run, the
   first call of rs is analysed while no other cell points to the block that
   realloc releases. Before the second call, the global variable q points to
   this block. The call does not read q, and q is not in the key of the call
   that memexec stored: the second call is a hit, which sweeps q as realloc
   sweeps it in the run without memexec. The sweep replaces the pointer by
   an escaping address when realloc frees a strong block, and joins the
   pointer with this address when the free is weak: when realloc frees a
   weak block, or the blocks of a pointer with two targets. */

#include <stdlib.h>
#include "__fc_builtin.h"

char *g;
char *q;
int x;

/* realloc of the block of g, to 8 bytes. */
char *rs(void) {
  return realloc(g, 8);
}

/* Run 0: realloc of a strong block, which realloc removes. */
void strong_main(void) {
  g = malloc(4);
  g[0] = 1; g[1] = 2; g[2] = 3; g[3] = 4;
  char *p = rs();
  g = malloc(4);
  g[0] = 1; g[1] = 2; g[2] = 3; g[3] = 4;
  q = g;
  char *r = rs();
  x = r[3];
}

/* Run 1: realloc of a weak block, which realloc does not remove. */
void weak_main(void) {
  /*@ eva_allocate fresh_weak; */
  g = malloc(4);
  g[0] = 1; g[1] = 2; g[2] = 3; g[3] = 4;
  char *p = rs();
  /*@ eva_allocate fresh_weak; */
  g = malloc(4);
  g[0] = 1; g[1] = 2; g[2] = 3; g[3] = 4;
  q = g;
  char *r = rs();
  x = r[3];
}

/* Run 2: realloc of a pointer with two targets. q points to one of them. */
void two_main(void) {
  char *a = malloc(4);
  char *b = malloc(4);
  a[0] = 1; a[1] = 1; a[2] = 1; a[3] = 1;
  b[0] = 2; b[1] = 2; b[2] = 2; b[3] = 2;
  g = Frama_C_interval(0, 1) ? a : b;
  a = 0; b = 0;
  char *p = rs();
  char *c = malloc(4);
  char *d = malloc(4);
  c[0] = 1; c[1] = 1; c[2] = 1; c[3] = 1;
  d[0] = 2; d[1] = 2; d[2] = 2; d[3] = 2;
  g = Frama_C_interval(0, 1) ? c : d;
  q = c;
  c = 0; d = 0;
  char *r = rs();
  x = r[0];
}
