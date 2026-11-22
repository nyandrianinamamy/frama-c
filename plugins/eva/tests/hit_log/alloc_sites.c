/* run.config
   STDOPT: +"-main same_line"
   STDOPT: +"-main hidden -eva-unroll-recursive-calls 10 -eva-no-alloc-returns-null"
*/

/* The allocated blocks are created by each analysis, with another identity
   in each project. The observer matches them across projects by the
   callstack of the call that created them, which ends with its call
   statement, not by their name, which tells neither.

   In same_line, two calls of malloc on one source line create two blocks
   whose names differ only by the suffix of a counter.

   In hidden, the recursive call f(0, 0) creates a block and frees it, as
   malloc does not fail; the call f(0, 1) of hidden creates a block on
   another callstack and keeps it in p. Both are named after f and the line
   of the call. The body of f is unavailable with -eva-hit-log (unrolled
   recursive calls), so the first block is in no answer of this run, while
   it is in those of the run without memexec: matched by their names and
   their rank among the blocks of the answers, the block of p would be
   matched to the first block, and the final state would not be that of the
   reference on p. */

#include <stdlib.h>

void *p;

void same_line(void) {
  p = malloc(4); A: ; p = malloc(4); B: ;
}

void f(int n, int keep) {
  if (n) f(n - 1, keep);
  else {
    int *t = malloc(4);
    if (keep) p = t; else free(t);
  }
}

void hidden(void) {
  f(1, 0);
  f(0, 1);
}
