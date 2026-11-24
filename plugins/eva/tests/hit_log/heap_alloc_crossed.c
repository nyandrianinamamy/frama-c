/* run.config
   MODULE: hit_log_observer heap_alloc
   STDOPT: +"-eva-no-alloc-returns-null -main crossed_main -eva-slevel 10"
*/

/* #127: the candidate condition, with candidates of the same number on
   each side and numbers that differ. keep_two reads the block of other and
   writes a new value of last. The second call of each loop reuses the
   block of rank 0 of its stack, which exists, and makes it weak. Before the
   second call of the first loop, last points to this candidate and other to
   x; before the second call of the second loop, other points to the
   candidate and last to y. x, y and the two candidates are strong blocks of
   one int of value 1: the two calls have the same numbered start state,
   last to #0 and other to #1. The candidate is #0 in the first call and #1
   in the second: the candidate condition fails, and the second call of the
   second loop is analysed. Each run is compared by the observer with the
   run without memexec; heap_alloc.ml compares the tables of the allocated
   blocks. */

#include <stdlib.h>

int *last, *other;

int *new_one(void) {
  int *p = malloc(sizeof *p);
  *p = 1;
  return p;
}

void keep_two(void) {
  int v = *other;
  last = malloc(sizeof(int));
  *last = v;
  KT: ;
}

void crossed_main(void) {
  int *x = new_one();
  int *y = new_one();
  other = x;
  for (int i = 0; i < 2; i++) keep_two();
  for (int i = 0; i < 2; i++) {
    if (i) { other = last; last = y; }
    keep_two();
  }
  CR: ;
}
