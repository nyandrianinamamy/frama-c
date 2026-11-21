/* run.config
   PLUGIN: eva,inout,scope
   STDOPT: +"-main below -eva-verbose 1 -eva-msg-key=final-states -eva-remove-redundant-alarms"
   STDOPT: +"-main below_child -eva-verbose 1 -eva-msg-key=final-states"
*/

/* The passes after the iteration on calls below a hit. The options
   -eva-verbose 1 and -eva-msg-key=final-states print the summary and the
   values at the end of each function. The run without memexec analyses
   every call. */

#include "__fc_builtin.h"

int c, g, h, k, r, t[10];

/* leaf is called by f only. The second call of f is a hit of the first, so
   that leaf is reached on the callstack of the analysed call and on a
   callstack below the hit. The third call of f is analysed. Before the reads
   of t, *p is {0; 3; 4} on the first two calls and {3; 9} on the third, so
   the two reads have the same alarm on the third call. The alarm does not
   reduce *p or c: Scope removes the second one. The assertion "valid" holds
   and the assertion "unknown" is unknown. */
void leaf(int *p) {
  if (c) *p = k;
  r = t[*p + c];
  r = t[*p + c];
  /*@ assert valid: *p <= 9; */
  /*@ assert unknown: *p == 3; */
}

void f(void) { int x; if (c) g = 0; x = g; leaf(&x); g = x; }

void below(void) {
  c = Frama_C_interval(0, 1); k = 3;
  g = 4; h = 7; f();
  g = 4; h = 8; f();
  g = 9; h = 8; f();
}

/* leaf2 is analysed once, called from below_child with h = 7. The first call
   of f2 is analysed, with h = 8, and its call of leaf2 is a hit. The second
   call of f2 is a hit, with h = 9, and leaf2 is called below it. h is not in
   the matching key of leaf2. The assertions use the label L: Eva evaluates
   them after the iteration, by the pass on the statuses of the properties,
   from the state at L on each callstack that reaches them. On the three
   callstacks, h is 7, 8 and 9 at L: the first assertion holds, the second
   is false on the callstack below the hit only, and the third is false on
   every callstack. */
void leaf2(void) {
  if (c) g = k;
 L:
  g++;
  /*@ assert label_valid: \at(h, L) >= 7; */
  /*@ assert label_below: \at(h, L) <= 8; */
  /*@ assert label_invalid: \at(h, L) < 7; */
}

void f2(void) { leaf2(); }

void below_child(void) {
  c = Frama_C_interval(0, 1); k = 3;
  g = 4; h = 7; leaf2();
  g = 4; h = 8; f2();
  g = 4; h = 9; f2();
}
