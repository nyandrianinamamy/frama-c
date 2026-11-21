/* run.config*
   STDOPT: +"-main worked"
   STDOPT: +"-main worked -eva-no-memexec"
   STDOPT: +"-main nonterm"
   STDOPT: +"-main nonterm -eva-no-memexec"
   STDOPT: +"-main logic"
   STDOPT: +"-main logic -eva-no-memexec"
   STDOPT: +"-main nested"
   STDOPT: +"-main nested -eva-no-memexec"
*/

/* The matching key of memexec holds the blocks that a call and its callees
   read or write, on any path, and the blocks read by the annotations of the
   call and of its callees. Each case is analysed with and without memexec;
   the calls reused are those with a "Reusing old results" message. */

#include "__fc_builtin.h"

int c, g, h, k;

/* g is in the key although every path through worked_f overwrites it, so
   the third call is analysed. The second and fourth calls differ from the
   one before only on h, and are reused. */
void worked_f(void) { if (c) g = 0; P: g = 1; }

void worked(void) {
  c = Frama_C_interval(0, 1);
  g = 4; h = 7; worked_f();
  g = 4; h = 8; worked_f();
  g = 9; h = 8; worked_f();
  g = 9; h = 5; worked_f();
}

/* nonterm_f never returns, and writes g. g is in the key, so the second
   call is analysed. */
void nonterm_f(void) { if (c) g = 1; while (1) {} }

void nonterm(void) {
  c = Frama_C_interval(0, 1);
  if (Frama_C_interval(0, 1)) {
    g = 4;
    nonterm_f();
  } else {
    g = 9;
    nonterm_f();
  }
}

/* g is read only by an assertion of logic_leaf. It is in the key of its
   caller logic_f, so the second call of logic_f is analysed and r2 is not
   restricted by g = 3. */
int a, out, r1, r2;

void logic_leaf(void) { /*@ assert a <= g; */ out = a; }

void logic_f(void) { logic_leaf(); }

void logic(void) {
  a = Frama_C_interval(0, 9); g = 3; logic_f(); r1 = out;
  a = Frama_C_interval(0, 9); out = 0; g = 9; logic_f(); r2 = out;
}

/* The second call of nested_f is reused, the third is analysed, and so is
   the call of nested_leaf within it. */
void nested_leaf(int *p) { if (c) *p = k; Q: *p = *p + 1; }

void nested_f(void) { int x; if (c) g = 0; x = g; nested_leaf(&x); g = x; }

void nested(void) {
  c = Frama_C_interval(0, 1);
  k = 3;
  g = 4; h = 7; nested_f();
  g = 4; h = 8; nested_f();
  g = 9; h = 8; nested_f();
}
