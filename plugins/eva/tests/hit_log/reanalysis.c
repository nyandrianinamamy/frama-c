/* run.config
   MODULE: @PTEST_NAME@
   STDOPT: +"-main by_address"
*/

/* The memoised answers on one callstack (#116) are reset when the analysis
   runs again in the same project. reanalysis.ml makes the requests before
   and after P in set, on each callstack, after an analysis without
   -eva-initialized-locals, then again after an analysis with it: x is
   uninitialized in the first answers and initialized in the second ones.
   The program is the case by_address of below_hit.c: the calls of set are
   below a hit. */

#include "__fc_builtin.h"

int c, h, k, out;

void set(int *p) { P: if (c) *p = k; Q: out = 1; }

void local_parent(void) { int x; set(&x); }

void by_address(void) {
  c = Frama_C_interval(0, 1); k = 3;
  out = 0; h = 7; local_parent();
  out = 0; h = 8; local_parent();
}
