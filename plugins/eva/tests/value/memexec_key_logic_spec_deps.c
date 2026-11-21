/* run.config
   MODULE: @PTEST_NAME@
   OPT: -eva @EVA_OPTIONS@
   OPT: -eva @EVA_OPTIONS@ -eva-no-memexec
*/
/* run.config*
   DONTRUN:
*/
/* Eva reduces k to zero before resolving the assigns destination of choose.
   Resolving it in the larger call start state fails on opaque(0). The logic
   dependencies must then be incomplete, not just {k, p}: after the assignment
   the postcondition reads t. The accompanying public API probe checks this
   directly, since the unknown output zone already prevents a cache hit. */

#include "__fc_builtin.h"
int k, t, *p, first, second;

/*@ logic int **opaque(integer x); */
/*@ requires k == 0;
    assigns *(k == 0 ? &p : opaque(0)) \from &t;
    ensures p == &t;
    ensures *p <= 3; */
void choose(void);

void f(void) { choose(); }

int main(void) {
  k = Frama_C_interval(0, 1); p = 0;
  t = Frama_C_interval(0, 3); f(); first = t;
  k = Frama_C_interval(0, 1); p = 0;
  t = Frama_C_interval(0, 9); f(); second = t;
}
