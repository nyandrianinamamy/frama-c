/* run.config
   PLUGIN: eva,inout,scope
   STDOPT: +"-eva-verbose 1 -eva-msg-key=final-states -eva-remove-redundant-alarms"
*/

/* The nested example of #87 (function nested of boundary.c), with an alarm
   on two reads and an assertion that mentions a C label in leaf, for the
   passes after the iteration. The second call of f is a hit of the first,
   and leaf is called below it; the third call of f is analysed. In leaf,
   the two reads of t, at Q, have the same alarm on the third call, where *p
   is {0; 3; 9} and *p + c can be 10. The alarm reduces neither *p nor c:
   Scope removes the second one. During the iteration, the assertion at_Q
   gets the status unknown, as Eva does not evaluate a C label there; after
   it, the pass on the statuses of the properties evaluates the assertion
   from the state at Q on each callstack, the callstack below the hit
   included: it holds on each, and gets the status valid. t is never written
   and r is 0 at each call: the second call of f is still a hit. */

#include "__fc_builtin.h"

int c, g, h, k, r, t[10];

void leaf(int *p) {
  if (c) *p = k;
 Q:
  r = t[*p + c];
  r = t[*p + c];
  *p = *p + 1;
  /*@ assert at_Q: \at(*p, Q) <= 9; */
}

void f(void) { int x; if (c) g = 0; x = g; P: leaf(&x); g = x; }

int main(void) {
  c = Frama_C_interval(0, 1); k = 3;
  g = 4; h = 7; f();
  g = 4; h = 8; f();
  g = 9; h = 8; f();
  return 0;
}
