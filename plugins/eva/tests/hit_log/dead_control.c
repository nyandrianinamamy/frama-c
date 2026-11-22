/* run.config
   DEPS: dead_below_crossing.c
   ENV: HIT_LOG_OBSERVER_SUMMARY @PTEST_NAME@.summary
   ENV: HIT_LOG_OBSERVER_UNAVAILABLE Dead
   LOG: @PTEST_NAME@.summary
   STDOPT: +"-eva-unroll-recursive-calls 10"
*/

/* Negative control of the case that the observer gives to an unavailable
   answer below a call that crosses a recursion, on the program of
   dead_below_crossing.c. There, Eva answers bottom at Dead, which the cache
   entry of leaf does not reach, and the observer is not asked for a case.

   Here, a control of the observer takes the answers with -eva-hit-log at
   Dead as unavailable, on the callstacks of the start of leaf, among which
   the call below the hit that crosses the recursion: what a rule that did
   not keep the unreached points unreachable would answer. The observer
   must give these answers no case of the closed list ("none" in its
   summary, which is printed), so that they count as failures: the case 3b
   is for the points that the cache entry reaches, as R. An observer that
   gave 3b to every point below the crossing would excuse them. */

#include "dead_below_crossing.c"
