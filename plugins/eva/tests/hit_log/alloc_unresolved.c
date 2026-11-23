/* run.config
   ENV: HIT_LOG_OBSERVER_SUMMARY @PTEST_NAME@.summary
   LOG: @PTEST_NAME@.summary
   STDOPT: +"-main issue94 -eva-slevel 20 -eva-no-alloc-returns-null -eva-mlevel 1"
*/

/* Allocated blocks whose match across projects is unresolved, under the
   known issue #94 (case 2 of known_issues.c: free on a reused call).

   Each iteration allocates a block in owner and frees it in release. Without
   memexec, the block is freed before the next allocation, and the call of
   malloc creates one block, reused by the three iterations. With memexec,
   the second call of release is a hit, which does not free the block: the
   next allocation finds it alive and, with -eva-mlevel 1, creates another
   block on the same callstack. The callstack of malloc thus creates one
   block in one project and several in the other: the observer cannot tell
   which block of one matches which block of the other, and the answers of
   the run with memexec, without recording, that hold these blocks are
   unresolved. The summary records them. With -eva-hit-log, release is a
   call that frees, and a hit on it removes the block: the run creates one
   block, as without memexec, and its answers are equal to the reference. */

#include <stdlib.h>

int *owner, *alias;

void release(void) { free(owner); owner = NULL; }

int issue94(void) {
  for (int i = 0; i < 3; ++i) {
    owner = malloc(sizeof *owner);
    if (!owner) return 0;
    *owner = 17;
    if (i) alias = owner; else alias = NULL;
    release();
  }
  return 0;
}
