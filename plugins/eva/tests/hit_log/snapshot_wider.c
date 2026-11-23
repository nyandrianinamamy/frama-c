/* run.config
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main wider_main"
*/

/* #123: a block mentioned through an actual argument beyond the formals,
   under the default options. keep_one is called through a pointer to a
   function type with more parameters: the extra argument is not bound to
   any formal, so the function cannot read it, and it is still an argument
   of the call. At i = 0, the call of malloc creates a strong block; at
   i = 1, it reuses that block, still live, and makes it weak. The arguments
   and the key are the same at both calls. */

#include <stdlib.h>

int keep_one(int x) { O: return 7; }

int r_one[2];
void wider_main(void) {
  int (*wider)(int, char *) = (int (*)(int, char *))keep_one;
  for (int i = 0; i < 2; i++) {
    char *b = malloc(1);
    r_one[i] = wider(0, b);
  }
}
