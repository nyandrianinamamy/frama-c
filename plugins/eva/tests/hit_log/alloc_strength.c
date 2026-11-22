/* run.config
   ENV: HIT_LOG_OBSERVER_ALLOC_REFERENCE fresh_weak
   STDOPT: +"-eva-alloc-builtin fresh -eva-no-alloc-returns-null"
   ENV: HIT_LOG_OBSERVER_ALLOC_REFERENCE fresh
   STDOPT: +"-eva-alloc-builtin fresh_weak -eva-no-alloc-returns-null"
*/

/* An allocated block is one block, a strong base, in one run, and a summary
   of the blocks allocated at its call, a weak base, in the other. The
   observer matches the two bases, which the same call creates, and keeps
   their strength in the comparison. A control of the observer gives the run
   without memexec another allocation policy than the command line.

   First run: the block is a summary without memexec and one block with
   -eva-hit-log. Before the store at W, the two states bind the block to the
   same uninitialized contents, and the store tells them apart: it replaces
   the contents of the one block, and adds 17 to those of the summary. The
   answers that hold the block are unresolved, at W as elsewhere: none is
   equal.

   Second run: the block is one block without memexec and a summary with
   -eva-hit-log. A state with the one block is among those of the summary:
   the answers cover the reference, at best, and none is equal. */

#include <stdlib.h>

int *p, r;

int main(void) {
  p = malloc(sizeof *p);
 W:
  *p = 17;
 R:
  r = *p;
  return r;
}
