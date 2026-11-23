/* run.config
   STDOPT: +"-eva-no-alloc-returns-null -main main1"
   STDOPT: +"-eva-no-alloc-returns-null -main main3"
*/

/* #119: a block freed by a callee. f frees the block of q, which its body
   never reads nor writes otherwise. Before #119, the rule took this block
   from the body-entry state of f at L, and from that of mid at M, after the
   call of f returns: the answer kept the freed block, [0] ∈ {7}, where the
   run without memexec has no such block. The answer covered the reference.
   f, mid and the entry points are heap calls: f calls free, mid and the
   entry points call f, and main1 and main3 call malloc. Their answers are
   the full states of their bodies. */

#include <stdlib.h>
char *g; int z;
void f(char *p) { free(p); L: ; }
void mid(char *p) { z = 1; f(p); M: ; }
void main1(void) {
  char *q = malloc(4); if (!q) return; q[0] = 7; g = q;
  f(q); A: ;
}
void main3(void) {
  char *q = malloc(4); if (!q) return; q[0] = 7; g = q;
  mid(q); A3: ;
}
