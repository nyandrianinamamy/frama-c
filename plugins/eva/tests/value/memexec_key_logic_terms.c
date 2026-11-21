/* run.config*
   STDOPT: +"-main extremum_case"
   STDOPT: +"-main extremum_case -eva-no-memexec"
   STDOPT: +"-main comprehension_case"
   STDOPT: +"-main comprehension_case -eva-no-memexec"
   STDOPT: +"-main location_conditional_case"
   STDOPT: +"-main location_conditional_case -eva-no-memexec"
   STDOPT: +"-main incomplete_conditional_case"
   STDOPT: +"-main incomplete_conditional_case -eva-no-memexec"
   STDOPT: +"-main dangling_case"
   STDOPT: +"-main dangling_case -eva-no-memexec"
   STDOPT: +"-main assigns_string_case"
   STDOPT: +"-main assigns_string_case -eva-no-memexec"
   STDOPT: +"-main incomplete_location_case"
   STDOPT: +"-main incomplete_location_case -eva-no-memexec"
   STDOPT: +"-main opaque_relation_case"
   STDOPT: +"-main opaque_relation_case -eva-no-memexec"
   STDOPT: +"-main opaque_range_case"
   STDOPT: +"-main opaque_range_case -eva-no-memexec"
*/

/* Dependencies of logic terms used by the matching key. Each entry point
   compares the changed call and an identical third call with a run without
   memexec. Progress messages identify the hits; the functions under test
   contain no observation builtin. */

#include "__fc_builtin.h"
#include <string.h>

int g, h, a, b, out, first, second, third;

/* The successful finite-range branch of the extended maximum must keep
   the reads of both bounds, even when its lambda reads no C variable. */
/*@ requires a <= \max(0, g, \lambda integer i; i); */
void extremum_f(void) { out = a; }

void extremum_case(void) {
  g = 3; a = Frama_C_interval(0, 9); extremum_f(); first = out;
  g = 9; out = 0; a = Frama_C_interval(0, 9); extremum_f(); second = out;
  h = 1; out = 0; a = Frama_C_interval(0, 9); extremum_f(); third = out;
}

/* Before narrowing i, the conditional can read g. After narrowing i to
   {g, 9}, i is nonzero and the same conditional only selects the constant
   arm. Collecting the predicate's reads after that narrowing loses g. */
/*@ requires a \in { i | integer i; i == (i == 0 ? g : 9) }; */
void comprehension_f(void) { out = a; }

void comprehension_case(void) {
  g = 3; a = Frama_C_interval(0, 9); comprehension_f(); first = out;
  g = 5; out = 0; a = Frama_C_interval(0, 9); comprehension_f(); second = out;
  h = 1; out = 0; a = Frama_C_interval(0, 9); comprehension_f(); third = out;
}

/* A conditional evaluated as a location reads its condition too. Explicit
   \from \nothing keeps this distinct from the missing-\from regression. */
void location_conditional_f(void) {
  /*@ assigns (g ? {b} : {a}) \from \nothing; */
  asm("");
}

void location_conditional_case(void) {
  a = 1; b = 2; g = 0; location_conditional_f(); first = a;
  a = 1; b = 2; g = 1; location_conditional_f(); second = b;
  a = 1; b = 2; h = 1; location_conditional_f(); third = b;
}

/* Failure to compute a condition's dependencies must reach its enclosing
   term. The unknown predicate prevents complete collection, so even the
   identical third call is analysed. */
/*@ predicate opaque_condition(integer x); */
/*@ requires a <= ((opaque_condition(0) || g == 0) ? 3 : 9); */
void incomplete_conditional_f(void) { out = a; }

void incomplete_conditional_case(void) {
  g = 0; a = Frama_C_interval(0, 9); incomplete_conditional_f(); first = out;
  g = 1; out = 0; a = Frama_C_interval(0, 9);
  incomplete_conditional_f(); second = out;
  h = 1; out = 0; a = Frama_C_interval(0, 9);
  incomplete_conditional_f(); third = out;
}

int *live = &h, *escaped;
int **pointer_cell;

/* \dangling reads both the address in pointer_cell and the pointed cell's
   danglingness. The pointer read must survive adding the latter zone. */
/*@ behavior small:
      assumes !\dangling(pointer_cell); requires a <= 3;
    behavior big:
      assumes \dangling(pointer_cell); requires a <= 9;
*/
void dangling_f(void) { out = a; }

void dangling_case(void) {
  { int dead; escaped = &dead; }
  pointer_cell = &live; a = Frama_C_interval(0, 9);
  dangling_f(); first = out;
  pointer_cell = &escaped; out = 0; a = Frama_C_interval(0, 9);
  dangling_f(); second = out;
  out = 0; a = Frama_C_interval(0, 9); dangling_f(); third = out;
}

char text[2];
int array[2];

/* A logic builtin used to select an assigns destination reads the pointed
   string, as it does inside a predicate. The cast selects its pointer form. */
void assigns_string_f(void) {
  /*@ assigns array[strlen((char *)text)] \from \nothing; */
  asm("");
}

void assigns_string_case(void) {
  array[0] = 1; array[1] = 2; text[0] = 0; text[1] = 0;
  assigns_string_f(); first = array[0];
  array[0] = 1; array[1] = 2; text[0] = 'x';
  assigns_string_f(); second = array[1];
  array[0] = 1; array[1] = 2; h = 1;
  assigns_string_f(); third = array[1];
}

/* The same incomplete condition as above, evaluated as a location. InOut
   must request strict dependencies for assigns destinations too. */
void incomplete_location_f(void) {
  /*@ assigns ((opaque_condition(0) || g == 0) ? {a} : {b}) \from \nothing; */
  asm("");
}

void incomplete_location_case(void) {
  a = 1; b = 2; g = 0; incomplete_location_f(); first = a;
  a = 1; b = 2; g = 1; incomplete_location_f(); second = b;
  a = 1; b = 2; h = 1; incomplete_location_f(); third = b;
}

/*@ logic integer opaque_value(integer x); */

/* An unsupported relation may leave values unchanged but still emit a
   warning depending on an earlier operand. At g = 0 the division raises
   a logic alarm first; at g = 1 Eva reaches the unsupported application. */
void opaque_relation_f(void) {
  /*@ check 1 / g == opaque_value(0); */
  out = 0;
}

void opaque_relation_case(void) {
  g = 0; opaque_relation_f();
  g = 1; opaque_relation_f();
  h = 1; opaque_relation_f();
}

/* A range bound that always fails has the same diagnostic dependency.
   Ignoring the bound's value does not justify ignoring its reads. */
void opaque_range_f(void) {
  /*@ check \valid(array + (0 .. (1 / g + opaque_value(0)))); */
  out = 0;
}

void opaque_range_case(void) {
  g = 0; opaque_range_f();
  g = 1; opaque_range_f();
  h = 1; opaque_range_f();
}
