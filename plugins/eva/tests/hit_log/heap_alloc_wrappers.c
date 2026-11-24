/* run.config
   MODULE: hit_log_observer heap_alloc
   STDOPT: +"-eva-no-alloc-returns-null -main wrap2_main -eva-alloc-functions malloc,calloc,realloc,inner_wrap,outer_wrap"
*/

/* #127: two levels of allocation wrappers. With inner_wrap and outer_wrap
   in -eva-alloc-functions, the policy by_stack removes the calls of malloc
   and of inner_wrap from the stack of the allocation, which ends with the
   call of outer_wrap. This stack ends above the call of inner_wrap, and at
   the call of outer_wrap: memexec stores neither. use_wrap, which calls
   outer_wrap, is stored, and its second call, from another call site, is a
   hit. Each run is compared by the observer with the run without memexec;
   heap_alloc.ml compares the tables of the allocated blocks. */

#include <stdlib.h>

int *inner_wrap(void) { return malloc(sizeof(int)); }
int *outer_wrap(void) { return inner_wrap(); }

int *use_wrap(void) {
  int *p = outer_wrap();
  *p = 1;
  return p;
}

void wrap2_main(void) {
  int *a = use_wrap();
  int *b = use_wrap();
  W2: ;
}
