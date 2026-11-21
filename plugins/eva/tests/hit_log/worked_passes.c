/* run.config
   PLUGIN: eva,inout,scope
   STDOPT: +"-eva-verbose 1 -eva-msg-key=final-states -eva-remove-redundant-alarms"
*/

/* The worked example of #87 (worked.c), with an alarm on two reads and an
   assertion that mentions a C label, for the passes after the iteration.
   In f, the two reads of t have the same alarm on the calls C and D, where
   g + c can be 10. The alarm reduces neither g nor c: Scope removes the
   second one. During the iteration, the assertion at_P gets the status
   unknown, as Eva does not evaluate a C label there; after it, the pass on
   the statuses of the properties evaluates the assertion from the state at P
   on each callstack, B and D included: it holds on each, and gets the status
   valid. t is never written and r is 0 at each call: the matching key of f
   is {c, g, r, t}, and the calls B and D are hits of the entries of A and C,
   as in the worked example. */

#include "__fc_builtin.h"

int c, g, h, r, t[10];

void f(void) {
  if (c) g = 0;
 P:
  r = t[g + c];
  r = t[g + c];
  /*@ assert at_P: \at(g, P) <= 9; */
  g = 1;
}

int main(void) {
  c = Frama_C_interval(0, 1);
  g = 4; h = 7; f();
  g = 4; h = 8; f();
  g = 9; h = 8; f();
  g = 9; h = 5; f();
  return 0;
}
