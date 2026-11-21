/* run.config*
   STDOPT: +"-main conditional_case"
   STDOPT: +"-main conditional_case -eva-no-memexec"
   STDOPT: +"-main diagnostics_case"
   STDOPT: +"-main diagnostics_case -eva-no-memexec"
   STDOPT: +"-main initialized_case"
   STDOPT: +"-main initialized_case -eva-no-memexec"
   STDOPT: +"-main separated_case"
   STDOPT: +"-main separated_case -eva-no-memexec"
   STDOPT: +"-main term_let_case"
   STDOPT: +"-main term_let_case -eva-no-memexec"
   STDOPT: +"-main tagged_assumes_case"
   STDOPT: +"-main tagged_assumes_case -eva-no-memexec"
   STDOPT: +"-main asm_target_case -eva-warn-key assigns:missing=warning"
   STDOPT: +"-main asm_target_case -eva-warn-key assigns:missing=warning -eva-no-memexec"
   STDOPT: +"-main spec_pre_case"
   STDOPT: +"-main spec_pre_case -eva-no-memexec"
   STDOPT: +"-main silent_contract_case"
   STDOPT: +"-main silent_contract_case -eva-no-memexec"
*/

/* The first two calls differ on a dependency of an annotation or assigns
   destination. The second must be analysed. Where there is a third call,
   it changes only frame: it must be a hit with the same final values and
   diagnostics as the run without memexec. */

#include "__fc_builtin.h"

int g, h, a, b, out, frame, *p;
int first, second, third;
int table[4];

/* The condition contributes dependencies even when only one arm is read. */
/*@ requires a <= (g ? 9 : 3); */
void conditional_f(void) { out = a; }

void conditional_case(void) {
  g = 0; a = Frama_C_interval(0, 9); conditional_f(); first = out;
  g = 1; a = Frama_C_interval(0, 9); out = 0;
  conditional_f(); second = out;
  frame = 1; a = Frama_C_interval(0, 9); out = 0;
  conditional_f(); third = out;
}

/* The missing condition dependency also suppressed an array-index alarm. */
/*@ requires a <= (g ? 9 : 3); */
void diagnostics_f(void) { out = table[a]; }

void diagnostics_case(void) {
  g = 0; a = Frama_C_interval(0, 9); diagnostics_f();
  g = 1; a = Frama_C_interval(0, 9); out = 0; diagnostics_f();
  frame = 1; a = Frama_C_interval(0, 9); out = 0; diagnostics_f();
}

/* Reading the contents of a tset must preserve the read of its address. */
/*@ behavior small: assumes \initialized(p); requires a <= 3;
    behavior big: assumes !\initialized(p); requires a <= 9; */
void initialized_f(void) { out = a; }

void initialized_case(void) {
  int x = 1, y;
  p = &x; a = Frama_C_interval(0, 9); initialized_f(); first = out;
  p = &y; a = Frama_C_interval(0, 9); out = 0;
  initialized_f(); second = out;
  frame = 1; a = Frama_C_interval(0, 9); out = 0;
  initialized_f(); third = out;
}

/*@ behavior small: assumes \separated(p, &h); requires a <= 3;
    behavior big: assumes !\separated(p, &h); requires a <= 9; */
void separated_f(void) { out = a; }

void separated_case(void) {
  p = &g; a = Frama_C_interval(0, 9); separated_f(); first = out;
  p = &h; a = Frama_C_interval(0, 9); out = 0;
  separated_f(); second = out;
  frame = 1; a = Frama_C_interval(0, 9); out = 0;
  separated_f(); third = out;
}

/* The dependency of a let binding survives evaluation of its body. */
/*@ requires a <= (\let z = g; z); */
void term_let_f(void) { out = a; }

void term_let_case(void) {
  g = 3; a = Frama_C_interval(0, 9); term_let_f(); first = out;
  g = 9; a = Frama_C_interval(0, 9); out = 0;
  term_let_f(); second = out;
  frame = 1; a = Frama_C_interval(0, 9); out = 0;
  term_let_f(); third = out;
}

/* Active_behaviors evaluates these assumes despite their no_eva names. */
/*@ behavior small: assumes no_eva: g == 0; requires a <= 3;
    behavior big: assumes no_eva: g != 0; requires a <= 9; */
void tagged_assumes_f(void) { out = a; }

void tagged_assumes_case(void) {
  g = 0; a = Frama_C_interval(0, 9); tagged_assumes_f(); first = out;
  g = 1; a = Frama_C_interval(0, 9); out = 0;
  tagged_assumes_f(); second = out;
  frame = 1; a = Frama_C_interval(0, 9); out = 0;
  tagged_assumes_f(); third = out;
}

/* With no from clause, evaluating the assigns address still reads p. */
void asm_target_f(void) { /*@ assigns *p; */ asm(""); }

void asm_target_case(void) {
  a = 1; b = 2; p = &a; asm_target_f(); first = a;
  a = 1; b = 2; p = &b; asm_target_f(); second = b;
  a = 1; b = 2; frame = 1; asm_target_f(); third = b;
}

/* Eva resolves the destination after reducing by requires. The dependency
   reconstruction cannot resolve it in the earlier state, so it must mark
   the result incomplete instead of keeping a state where p was not written.
   InOut already refused reuse for this example before the correction; this
   regression also preserves the observable final state of that path. */
int k, t;
/*@ logic int **opaque(integer x); */
/*@ requires k == 0;
    assigns *(k == 0 ? &p : opaque(0)) \from &t;
    ensures p == &t;
    ensures *p <= 3; */
void spec_pre_choose(void);

void spec_pre_f(void) { spec_pre_choose(); }

void spec_pre_case(void) {
  k = Frama_C_interval(0, 1); p = 0; t = Frama_C_interval(0, 3);
  spec_pre_f(); first = t;
  k = Frama_C_interval(0, 1); p = 0; t = Frama_C_interval(0, 9);
  spec_pre_f(); second = t;
}

/* Dependency collection explores the otherwise short-circuited let. It
   must report incompleteness silently when the binding is uninitialized. */
/*@ requires g == 0 || (\let z = *p; z == z); */
void silent_contract_f(void) { }

void silent_contract_case(void) {
  int u;
  p = &u; g = 0; silent_contract_f();
}
