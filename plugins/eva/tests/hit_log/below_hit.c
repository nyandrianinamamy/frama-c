/* run.config
   STDOPT: +"-main by_address"
   STDOPT: +"-main by_address -eva-initialized-locals"
   STDOPT: +"-main two_levels"
   STDOPT: +"-main formal"
   STDOPT: +"-main one_site -eva-slevel 4"
   STDOPT: +"-main assertion"
   STDOPT: +"-main precondition"
   STDOPT: +"-main by_spec -eva-use-spec spec_child"
*/

/* Calls below a hit. In each case, a parent function is called twice, and
   the second call differs from the first only on h, which neither the parent
   nor its callees read: it is a hit. The calls made by the body of the
   parent are then below a hit: their body does not run, and their states are
   rebuilt from the calls stored in the cache entry of the parent. */

#include "__fc_builtin.h"

int c, g, h, k, out, t;

/* A local of the caller passed by address and not yet written at the call.
   The local exists in the start state of set and not in that of
   local_parent: it is kept by the stored start state of the call. With
   -eva-initialized-locals, it has a value at the call. */
void set(int *p) { P: if (c) *p = k; Q: out = 1; }

void local_parent(void) { int x; set(&x); }

void by_address(void) {
  c = Frama_C_interval(0, 1); k = 3;
  out = 0; h = 7; local_parent();
  out = 0; h = 8; local_parent();
}

/* Two levels below a hit, through a child that was itself a hit when the
   parent was analysed: the call of mid in the first call of top is a hit of
   the first call of mid. leaf2 is below this hit, and two levels below the
   hit of top. */
void leaf2(void) { P: out = g + 1; }

void mid(void) { leaf2(); }

void top(void) { mid(); }

void two_levels(void) {
  g = 1; out = 0; h = 6; mid();
  g = 1; out = 0; h = 7; top();
  g = 1; out = 0; h = 8; top();
}

/* A callee with a formal: below the hit, the start of child gives x bound to
   the argument, and h from the hit. */
void child(int x) { P: g = x; }

void formal_parent(void) { child(7); }

void formal(void) {
  g = 0; h = 7; formal_parent();
  g = 0; h = 8; formal_parent();
}

/* Two calls of two at one call statement, kept apart by the slevel, with
   different arguments. They use two cache entries of different keys: the
   first reads x and writes s1, the second reads x and writes b. Both are on
   the same callstack, and the answer is their join. Before P, b is 7 after
   the call with x = 0, and 2 after the call with x = 1, from the stored start
   state of that call. Pasting the entry of the call with x = 1 on the start
   state of the call with x = 0 would give b = 1. */
int b, s1;

void two(int x) { if (x) s1 = 1; else b = 7; P: out = 1; }

void site_parent(void) {
  int y;
  if (c) { y = 0; b = 1; } else { y = 1; b = 2; }
  two(y);
}

void one_site(void) {
  c = Frama_C_interval(0, 1);
  b = 0; s1 = 0; out = 0; h = 7; site_parent();
  b = 0; s1 = 0; out = 0; h = 8; site_parent();
}

/* A callee with an assertion that reads t, which its caller does not touch
   otherwise: t is in the key of the caller through the logic inputs of its
   callee. The second call of assert_parent is a hit, with the same value of
   t; the third is analysed, as t differs. */
void asserted(void) { /*@ assert t <= 5; */ P: out = 1; }

void assert_parent(void) { asserted(); }

void assertion(void) {
  t = Frama_C_interval(0, 9); out = 0; h = 7; assert_parent();
  t = Frama_C_interval(0, 9); out = 0; h = 8; assert_parent();
  t = 2; out = 0; h = 8; assert_parent();
}

/* A precondition of the callee that reduces h, a block of the frame. Below
   the hit, the precondition is not evaluated: the body-entry state of the
   call of required is its start state, and h at P covers the value of the
   run without memexec. */
/*@ requires h >= 4; */
void required(void) { P: out = 1; }

void requires_parent(void) { required(); }

void precondition(void) {
  h = Frama_C_interval(0, 9); out = 0; requires_parent();
  h = Frama_C_interval(2, 9); out = 0; requires_parent();
}

/* A callee analysed by its specification: below the hit, its start gives
   its formal and h from the hit; it has no interior point. */
/*@ assigns out \from x; */
void spec_child(int x) { P: out = x; }

void spec_parent(void) { spec_child(5); }

void by_spec(void) {
  out = 0; h = 7; spec_parent();
  out = 0; h = 8; spec_parent();
}
