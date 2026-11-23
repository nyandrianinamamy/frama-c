/* run.config
   STDOPT: +"-eva-no-alloc-returns-null -main reallocarray_main"
*/

/* #119: reallocarray marks its call as a heap call, as realloc does in
   heap_builtins.c. raz reallocates a block allocated by its caller: the old
   block is freed. */

#include <stdlib.h>
char *g; int z;

void raz(int n) { z = n; g = reallocarray(g, n, 2); RA: ; z = 0; }
void reallocarray_main(void) {
  g = malloc(2); if (!g) return; g[0] = 1;
  raz(4); E: ;
}
