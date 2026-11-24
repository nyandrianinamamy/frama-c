/* run.config
   MODULE: hit_log_observer heap_alloc
   STDOPT: +"-eva-no-alloc-returns-null -main pair_main"
   STDOPT: +"-eva-no-alloc-returns-null -main level_main -eva-mlevel 1 -eva-slevel 10"
*/

/* #127: hits on calls that create two blocks. Each creation symbol of the
   stored call must be bound to the block that the replay creates in its
   place. Each run is compared by the observer with the run without
   memexec; heap_alloc.ml compares the tables of the allocated blocks. */

#include <stdlib.h>

/* Run 0: a call that creates two blocks, on two stacks. mk_pair allocates
   at two statements, each block with its own value. The second call is a
   hit that creates two blocks, one on each stack of its own call: each
   creation symbol is bound to the block created on its stack. pa and pb,
   which the call writes, are reset before the second call. */
int *pa, *pb;
void mk_pair(int v) {
  pa = malloc(sizeof(int));
  pb = malloc(sizeof(int));
  *pa = v;
  *pb = v + 1;
  MP: ;
}

void pair_main(void) {
  mk_pair(1);
  int *a = pa, *b = pb;
  pa = 0;
  pb = 0;
  mk_pair(1);
  PM: ;
}

/* Run 1: a call that creates two blocks on one stack. With -eva-mlevel 1,
   the second iteration of the loop of level finds the block of rank 0 in
   the state and creates the block of rank 1 on the same stack. The second
   call is a hit that creates the blocks of ranks 0 and 1 on the stack of
   its own call, in this order, each with its own value. l0 and l1 are
   reset before the second call. */
int *l0, *l1;
void level(void) {
  for (int i = 0; i < 2; i++) {
    int *p = malloc(sizeof *p);
    *p = i + 1;
    if (i == 0) l0 = p; else l1 = p;
  }
  LV: ;
}

void level_main(void) {
  level();
  int *a = l0, *b = l1;
  l0 = 0;
  l1 = 0;
  level();
  LE: ;
}
