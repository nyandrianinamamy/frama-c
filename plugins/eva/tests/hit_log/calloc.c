/* run.config
   STDOPT: +"-main alloc_once"
   STDOPT: +"-main alloc_twice"
   STDOPT: +"-main alloc_once -eva-alloc-builtin imprecise"
*/

/* A call that creates an allocated block is answered at its own points, with
   the content of the block. A call that creates a block is not reused by
   memexec: both calls are analysed. */

#include <stdlib.h>

struct S { int a; int b; } *p, *q;

void alloc(void) {
  p = calloc(1, sizeof *p);
 P: if (p) p->b = 1;
}

/* Two calls from two call sites: two blocks. */
void alloc_once(void) {
  alloc();
  q = p;
  if (q) q->a = 5;
  alloc();
}

/* Two calls from one call site: the second calloc allocates in the block of
   the first call, which becomes weak. The footprint of the second call does
   not hold the block: InOut does not report the write of calloc. The answer
   is still equal to that of the run without memexec: on this callstack, the
   first call gives the content written by calloc, and the update of a weak
   block keeps its former content. The third run, with a single block for all
   allocations, is the same case across two callstacks. */
void alloc_twice(void) {
  for (int i = 0; i < 2; i++) {
    alloc();
    if (p) p->a = 5;
  }
}
