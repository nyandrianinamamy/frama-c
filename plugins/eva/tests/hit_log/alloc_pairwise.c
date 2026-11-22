/* run.config
   ENV: HIT_LOG_OBSERVER_ALLOC_REFERENCE by_stack
   ENV: HIT_LOG_OBSERVER_ALLOC_MEMEXEC by_stack
   ENV: HIT_LOG_OBSERVER_SUMMARY @PTEST_NAME@.0.summary
   LOG: @PTEST_NAME@.0.summary
   OPT: -machdep x86_32 -eva-verbose 0 -eva-no-remove-redundant-alarms -eva-hit-log -eva-slevel 10 -eva-no-alloc-returns-null -eva-alloc-builtin by_stack
   ENV: HIT_LOG_OBSERVER_SUMMARY @PTEST_NAME@.1.summary
   LOG: @PTEST_NAME@.1.summary
   OPT: -machdep x86_32 -eva-verbose 0 -eva-no-remove-redundant-alarms -eva-hit-log -eva-slevel 10 -eva-no-alloc-returns-null -eva-alloc-builtin fresh
*/

/* The run with memexec and without recording is compared with the run
   without memexec between these two runs only. A control of the observer
   gives both the allocation policy by_stack, whatever the command line:
   their analyses are the same in the two runs of this test, where only the
   run with -eva-hit-log changes its policy, from by_stack to fresh.

   With by_stack, the two iterations allocate one block; with fresh, each
   allocates its own. In the second run of the test, the call of malloc
   creates one block without -eva-hit-log and two with it: the answers with
   -eva-hit-log that hold a block are unresolved. The verdicts of the run
   with memexec are those of the first run, all equal: the summary of the
   observer, which has them, is printed. */

#include <stdlib.h>

int *p;

int main(void) {
  for (int i = 0; i < 2; i++) {
    p = malloc(sizeof *p);
    *p = 17;
    free(p);
  }
  return 0;
}
