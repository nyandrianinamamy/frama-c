/* run.config
   MODULE: hit_log_observer heap_alloc heap_names
   STDOPT: +"-eva-no-alloc-returns-null -main wrap_main -eva-alloc-functions malloc,calloc,realloc,reallocarray,my_calloc,my_realloc,my_reallocarray"
*/

/* #129: allocation wrappers of calloc, realloc and reallocarray. With
   my_calloc, my_realloc and my_reallocarray in -eva-alloc-functions, and
   reallocarray, which the default of the option does not hold, the
   policy by_stack strips the call of the builtin from the stack of the
   allocation, which ends with the call of the wrapper: the creation is not
   below a call of the wrapper, which is not stored. The functions that call
   the wrappers are stored, and their second call, from another call site,
   is a hit. Each run is compared by the observer with the run without
   memexec; heap_alloc.ml compares the tables of the allocated blocks, and
   heap_names.ml the names of the blocks of the policy by_stack. */

#include <stdlib.h>

char *g;

char *my_calloc(void) { return calloc(2, 2); }
char *my_realloc(void) { return realloc(g, 8); }
char *my_reallocarray(void) { return reallocarray(g, 4, 2); }

char *use_calloc(void) {
  char *p = my_calloc();
  p[1] = 1;
  return p;
}

char *use_realloc(void) {
  char *p = my_realloc();
  p[5] = 1;
  return p;
}

char *use_reallocarray(void) {
  char *p = my_reallocarray();
  p[5] = 1;
  return p;
}

void wrap_main(void) {
  char *a = use_calloc();
  char *b = use_calloc();
  g = malloc(4);
  g[0] = 1; g[1] = 2; g[2] = 3; g[3] = 4;
  char *c = use_realloc();
  g = malloc(4);
  g[0] = 1; g[1] = 2; g[2] = 3; g[3] = 4;
  char *d = use_realloc();
  g = malloc(4);
  g[0] = 1; g[1] = 2; g[2] = 3; g[3] = 4;
  char *e = use_reallocarray();
  g = malloc(4);
  g[0] = 1; g[1] = 2; g[2] = 3; g[3] = 4;
  char *f = use_reallocarray();
}
