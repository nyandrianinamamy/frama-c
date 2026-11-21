/* run.config
   MODULE: @PTEST_NAME@
   STDOPT:
*/

/* An analysis of another project, with recording, started from a hook at
   the end of the call of main in the current one. The footprint of main,
   given before the hook, is kept: the requests of both projects are answered
   by the rule, as in worked.c. reentrant.ml makes the requests. */

#include "__fc_builtin.h"

int c, g, h;

void f(void) { if (c) g = 0; P: g = 1; }

int main(void) {
  c = Frama_C_interval(0, 1);
  g = 4; h = 7; f();
  g = 4; h = 8; f();
  g = 9; h = 8; f();
  g = 9; h = 5; f();
  return 0;
}
