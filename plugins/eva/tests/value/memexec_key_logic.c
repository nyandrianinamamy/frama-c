/* run.config*
   STDOPT: +"-main requires_case"
   STDOPT: +"-main requires_case -eva-no-memexec"
   STDOPT: +"-main assumes_case"
   STDOPT: +"-main assumes_case -eva-no-memexec"
   STDOPT: +"-main ensures_case"
   STDOPT: +"-main ensures_case -eva-no-memexec"
   STDOPT: +"-main spec_case"
   STDOPT: +"-main spec_case -eva-no-memexec"
   STDOPT: +"-main three_calls"
   STDOPT: +"-main three_calls -eva-no-memexec"
   STDOPT: +"-main assert_case"
   STDOPT: +"-main assert_case -eva-no-memexec"
   STDOPT: +"-main asm_case"
   STDOPT: +"-main asm_case -eva-no-memexec"
*/

/* The matching key of memexec holds the blocks that Eva reads to interpret
   the annotations and the contracts of a call and of its callees, and the
   blocks written by the assigns clauses of its asm statements. Each case is
   analysed with and without memexec: the final values must be the same.
   The calls reused are those with a "Reusing old results" message. */

#include "__fc_builtin.h"

int c, g, h, a, y, out, t, *p;
int r[9];

/* Case 1: requires clause of a function with a body. The requires clause
   of req_f reads g. The second call differs from the first on g and is
   analysed: r[1] is not restricted by g = 9. The third call differs from the
   second only on h, and is reused.
   The requires clause of req_false is false in its first call, whose body
   is not analysed. g is in the key nonetheless: the second call, where the
   clause holds, is analysed, and requires_case terminates. */

/*@ requires x >= g; */
int req_f(int x) { y = x + 1; return y; }

/*@ requires g > 0; */
void req_false(void) { out = 1; }

void requires_case(int n) {
  int v = n;
  g = 9; r[0] = req_f(v);
  v = n; g = 4; y = 0; r[1] = req_f(v);
  v = n; h = 1; y = 0; r[2] = req_f(v);
  c = Frama_C_interval(0, 1);
  g = 0; out = 0;
  if (c) req_false();
  g = 1; out = 0; req_false();
  r[3] = out;
}

/* Case 2: assumes clauses of a function with a body. They read g, which
   decides which requires clause restricts a. The second call is analysed,
   the third, which differs from the second only on h, is reused. */

/*@ behavior small: assumes g <= 3; requires a <= 3;
    behavior big: assumes g > 3; requires a <= 9; */
void assumes_f(void) { out = a; }

void assumes_case(void) {
  a = Frama_C_interval(0, 9); g = 3; assumes_f(); r[0] = out;
  a = Frama_C_interval(0, 9); g = 9; out = 0; assumes_f(); r[1] = out;
  a = Frama_C_interval(0, 9); h = 1; out = 0; assumes_f(); r[2] = out;
}

/* Case 3: ensures clause of a function with a body. It reads g. The second
   call is analysed, the third, which differs from the second only on h, is
   reused. */

/*@ ensures out <= g; */
void ensures_f(void) { out = a; }

void ensures_case(void) {
  a = Frama_C_interval(0, 9); g = 3; ensures_f(); r[0] = out;
  a = Frama_C_interval(0, 9); g = 9; out = 0; ensures_f(); r[1] = out;
  a = Frama_C_interval(0, 9); h = 1; out = 0; ensures_f(); r[2] = out;
}

/* Case 4: contract of a function analysed through its specification.
   The requires clause of spec_req reads g. The second call of its caller
   spec_req_caller is analysed, the third, which differs from the second
   only on h, is reused.
   The ensures clauses of spec_ptr dereference the pointer p that it
   assigns, and restrict t. t is in the key of its caller spec_ptr_caller:
   the second call is analysed and r[4] is restricted by g. */

/*@ requires a <= g; assigns \nothing; */
void spec_req(void);

void spec_req_caller(void) { spec_req(); out = a; }

/*@ assigns p \from &t;
    ensures p == &t;
    ensures *p <= g; */
void spec_ptr(void);

void spec_ptr_caller(void) { spec_ptr(); }

void spec_case(void) {
  a = Frama_C_interval(0, 9); g = 3; spec_req_caller(); r[0] = out;
  a = Frama_C_interval(0, 9); g = 9; out = 0; spec_req_caller(); r[1] = out;
  a = Frama_C_interval(0, 9); h = 1; out = 0; spec_req_caller(); r[2] = out;
  g = 9; p = 0; t = Frama_C_interval(0, 20); spec_ptr_caller(); r[3] = t;
  g = 9; p = 0; t = Frama_C_interval(0, 30); spec_ptr_caller(); r[4] = t;
}

/* Case 4, with calls in three contexts: the assumes clauses of pick read g.
   The third call of outer differs from the first on out and h, and is
   analysed. Its call of pick_f differs from the second call of pick_f only
   on g, which is in the key: it is analysed, and r[2] is not 42. */

/*@ behavior keep: assumes g == 0; assigns \nothing;
    behavior change: assumes g != 0; assigns out \from \nothing;
    complete behaviors; disjoint behaviors; */
void pick(void);

void pick_f(void) { pick(); }

void outer(void) { h = 7; pick_f(); }

void three_calls(void) {
  g = 1; out = 41; h = 1; outer(); r[0] = out;
  g = 0; out = 42; pick_f(); r[1] = out;
  g = 1; out = 42; h = 2; outer(); r[2] = out;
}

/* Case 5: assertions.
   Eva cannot evaluate the predicate opaque in the assertion of parts_f.
   The other part reads g, which is in the key: the second call is
   analysed. The third call, from the same state, is reused.
   The dependencies of the assertion of label_f cannot be computed, because
   of the label L. label_f and its caller label_caller are not stored: the
   third call of label_caller, from the same state as the second, is
   analysed.
   Eva does not reduce by the check of check_f, but emits its status: g is
   in the key, and the second call, which differs from the first only on g,
   is analysed and gives the status unknown. */

/*@ predicate opaque(integer x); */

void parts_f(void) { /*@ assert a <= g && opaque(0); */ out = a; }

void label_f(void) {
 L: /*@ assert a <= g && \at(a, L) == \at(a, L); */
  out = a;
}

void label_caller(void) { label_f(); }

void check_f(void) { /*@ check a <= g; */ out = a; }

void assert_case(void) {
  a = Frama_C_interval(0, 9); g = 3; out = 0; parts_f(); r[0] = out;
  a = Frama_C_interval(0, 9); g = 9; out = 0; parts_f(); r[1] = out;
  a = Frama_C_interval(0, 9); g = 9; out = 0; parts_f(); r[2] = out;
  a = Frama_C_interval(0, 9); g = 3; out = 0; label_caller(); r[3] = out;
  a = Frama_C_interval(0, 9); g = 9; out = 0; label_caller(); r[4] = out;
  a = Frama_C_interval(0, 9); g = 9; out = 0; label_caller(); r[5] = out;
  a = Frama_C_interval(0, 9); g = 9; out = 0; check_f(); r[6] = out;
  a = Frama_C_interval(0, 9); g = 3; out = 0; check_f(); r[7] = out;
}

/* Case 6: asm statements with an assigns clause. asm_write writes g, which
   is in the key: the second call is analysed, and the third, from the same
   state, is reused. asm_read writes in pa a value that depends on q: the
   second call is analysed, and pa points to g at the end. */

int *pa, *q;

void asm_write(void) { /*@ assigns g \from \nothing; */ asm(""); }

void asm_read(void) { /*@ assigns pa \from q; */ asm(""); }

void asm_case(void) {
  g = 4; asm_write(); r[0] = g;
  g = 9; asm_write(); r[1] = g;
  g = 9; asm_write(); r[2] = g;
  pa = 0; q = &a; asm_read();
  pa = 0; q = &g; asm_read();
}
