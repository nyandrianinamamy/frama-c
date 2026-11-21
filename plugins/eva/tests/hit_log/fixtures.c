/* run.config
   STDOPT: +"-main read_before_overwrite"
   STDOPT: +"-main guard"
   STDOPT: +"-main pointer_write"
   STDOPT: +"-main loop"
   STDOPT: +"-main widening_hints"
   STDOPT: +"-main scope"
   STDOPT: +"-main one_callstack"
   STDOPT: +"-main unreachable"
*/

/* In each case, the second call of the function differs from the first only
   on h, which the function does not read: it is a hit. */

#include "__fc_builtin.h"

volatile int v;
int a, c, g, h, out, w, x, y;
int t1, t2, *p;

/* A block read before being overwritten: a is in the key, with the same value
   at both calls. */
void rbo(void) { out = a; P: a = 5; }

void read_before_overwrite(void) {
  a = 1; out = 0; h = 7; rbo();
  a = 1; out = 0; h = 8; rbo();
}

/* A guard that reduces x on the branch. */
void guarded(void) { if (x > 3) { P: out = x; } }

void guard(void) {
  x = Frama_C_interval(0, 9); out = 0; h = 7; guarded();
  x = Frama_C_interval(0, 9); out = 0; h = 8; guarded();
}

/* A write through a pointer with two targets. */
void write_through(void) { *p = 3; P: w = 1; }

void pointer_write(void) {
  p = v ? &t1 : &t2;
  t1 = 0; t2 = 0; w = 0; h = 7; write_through();
  t1 = 0; t2 = 0; w = 0; h = 8; write_through();
}

/* A loop. */
void sum(void) {
  out = 0;
  for (int i = 0; i < 10; i++) out += i;
 P: w = out;
}

void loop(void) {
  out = 0; w = 0; h = 7; sum();
  out = 0; w = 0; h = 8; sum();
}

/* A loop whose widening hints differ between the two calls of count: the
   hint on x is added by discover, between them. The hit uses the cache entry
   computed without the hint: after the loop, x is [13..2147483647] on the
   hit, {13} in the run without memexec, so the answer covers. The point R is
   reachable in the cache entry and not in the run without memexec on the
   callstack of the hit, for the same reason. The bound is a formal: a
   comparison of x with a constant would be a widening hint itself. */
void count(int n) {
  while (x < n) ++x;
 P: if (x > n) { R: y = 1; }
}

void discover(int *q) {
  /*@ loop widen_hints *q, 13; */
  while (*q < 0) ++*q;
}

void widening_hints(void) {
  x = 0; y = 0; h = 7; count(13);
  discover(&x);
  x = 0; y = 0; h = 8; count(13);
}

/* A formal and a local, in and out of scope. */
void scoped(int f) {
  { int l = f + 1; out = l; }
 P: out++;
}

void scope(void) {
  out = 0; h = 7; scoped(2);
  out = 0; h = 8; scoped(2);
}

/* Two calls on one callstack: the second iteration of the loop calls once
   more from the same call site. */
void same_site(void) { P: w = g; }

void one_callstack(void) {
  for (int i = 0; i < 2; i++) { g = 0; w = 0; h = i; same_site(); }
}

/* A point unreachable in the cache entry, and on the hit. */
void dead_branch(void) { if (c) { P: g = 1; } }

void unreachable(void) {
  c = 0; g = 0; h = 7; dead_branch();
  c = 0; g = 0; h = 8; dead_branch();
}
