/* run.config
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main unused_main"
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -main varargs_main -no-variadic-translation"
*/

/* #123: blocks mentioned through the arguments only. Neither function reads
   the pointer it receives: the block is neither in its key nor pointed to
   by a value of its key. At i = 0, the call of malloc creates a strong
   block; at i = 1, it reuses that block, still live, and makes it weak. The
   arguments and the key are the same at both calls. */

#include <stdlib.h>

/* A formal that the body never reads. */
int keep_unused(char *unused) { U: return 7; }

int r_unused[2];
void unused_main(void) {
  for (int i = 0; i < 2; i++) {
    char *p = malloc(1);
    r_unused[i] = keep_unused(p);
  }
}

/* An actual argument beyond the formals of a variadic function. Option
   -no-variadic-translation keeps the call as written: the pointer is passed
   as an extra argument. With the translation, the function would receive a
   pointer to an array of the caller, outside the allocated blocks. */
int keep_va(int x, ...) { V: return 7; }

int r_va[2];
void varargs_main(void) {
  for (int i = 0; i < 2; i++) {
    char *b = malloc(1);
    r_va[i] = keep_va(0, b);
  }
}
