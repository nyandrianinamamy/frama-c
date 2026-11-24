/* run.config
   MODULE: hit_log_observer heap_alloc heap_names
   STDOPT: +"-eva-no-alloc-returns-null -main stale_main -eva-slevel 10"
*/

/* #130: Decision 2 of #126 with a hit that renames a block. The automatic
   release at the end of maybe releases every block of alloca that the
   table of the allocated blocks gives to the callstack of maybe: on the
   second and third calls of user, the block that the first call made,
   already released and absent from the state. The call of user then sweeps
   a block that it neither creates nor has among its candidates, which has
   no number: memexec does not store it. The third call has the input of the
   second, except that q points to b where the second has a: if memexec
   stored the second call, the third would be a hit that renames a into b,
   and whose sweep names a block that the renaming does not map.
   heap_alloc.ml and heap_names.ml compare the tables and the names of the
   allocated blocks with those of the run without memexec. */

#include <alloca.h>
#include <stdlib.h>

int x;

void maybe(int n) {
  if (n) {
    char *s = alloca(4);
    *s = 1;
  }
}

void user(int *q, int n) {
  maybe(n);
  *q = 1;
}

void stale_main(void) {
  int *a = malloc(sizeof(int));
  int *b = malloc(sizeof(int));
  for (int i = 0; i < 3; i++) {
    *a = 0;
    *b = 0;
    user(i == 2 ? b : a, i == 0);
  }
  x = *a + *b;
}
