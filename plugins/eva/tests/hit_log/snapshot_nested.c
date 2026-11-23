/* run.config
   STDOPT: +"-eva-no-alloc-returns-null -eva-slevel 10 -eva-unroll-recursive-calls 3 -main nested_main"
*/

/* #123: several results that memexec keeps for one input state, and whose
   snapshots fail at the same lookup. At i = 0, nested calls itself with
   the same input state: the inner calls are stored during the analysis of
   the outer one, and memexec keeps three results for that state. Beyond
   depth 3, the call uses the assigns clause. At i = 1, calloc reuses the
   block of gp, still live, and makes it weak; x no longer holds 0 at the
   outer call. The call at depth 1 has the input state of the three
   results, none of which holds: memexec removes all of them, and the call
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
