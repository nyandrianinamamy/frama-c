/* run.config
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main key_main"
*/

/* #123: a block mentioned only through the values of the key. cmp_key has
   no argument: it reads gp and gq, which point to the block, and
   dereferences neither. At i = 0, the call of malloc creates a strong
   block; at i = 1, it reuses that block, still live, and makes it weak.
   The key of cmp_key has the same content at both calls: without the
   snapshot of the blocks that the values of its key point to, memexec
   would reuse the first call for the second one, which would compare a
   weak block as if it were strong. */

#include <stdlib.h>

char *gp, *gq;

int cmp_key(void) { K: return gp == gq; }

int r_key[2];
void key_main(void) {
  for (int i = 0; i < 2; i++) {
    char *b = malloc(1);
    if (i == 0) { gp = b; gq = b; }
    r_key[i] = cmp_key();
  }
}
