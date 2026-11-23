/* run.config
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -eva-unroll-recursive-calls 3 -main nested_main"
*/

/* #123: several results that memexec keeps for one input state. At i = 0,
   nested calls itself with the same input state: the inner calls are
   stored during the analysis of the outer one, and memexec keeps three
   results for that state. At depth 3, the call uses the assigns clause. At
   i = 1, calloc reuses the block of gp, still live, and makes it weak; x
   no longer holds 0 at the outer call. #125: in the numbered input state
   of the call at depth 1, a weak placeholder stands for the block, where
   the three results have a strong one: the call misses on its content and
   is analysed. The points of the body of nested are unavailable, as for
   any function analysed with unrolled recursive calls (closed list of
   #87). */

#include <stdlib.h>

volatile int v;
int *gp;
int x;

/*@ assigns x \from *gp, v; */
void nested(void) {
  x = *gp;
  if (v) nested();
}

void nested_main(void) {
  for (int i = 0; i < 2; i++) {
    gp = calloc(1, sizeof *gp);
    nested();
  }
}
