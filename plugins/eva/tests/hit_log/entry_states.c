/* run.config
   STDOPT: +"-main aggregate"
   STDOPT: +"-main requires_untouched"
   STDOPT: +"-main requires_read"
   STDOPT: +"-main no_body_entry"
*/

/* The two entry states of a call: the start state, after the binding of the
   arguments, and the body-entry state, after the preconditions. */

#include "__fc_builtin.h"

volatile int v;
int g, x, out;

/* An aggregate argument that the body does not read is not in the matching
   key: the second call, with the fields swapped, can be a hit of the first.
   Its field s.a before P is then 2, taken from its own entry state. */
struct S { int a; int b; };

void agg(struct S s) { P: g = 1; }

void aggregate(void) {
  struct S s1 = { 1, 2 };
  g = 0;
  agg(s1);
  struct S s2 = { 2, 1 };
  g = 0;
  agg(s2);
}

/* The start of the function gives g in [0..9], the first statement gives
   g in [4..9], on the analysed call and on the hit. g is not in the key of
   req_untouched: the reads of a requires clause are not tracked (#86). */
/*@ requires g >= 4; */
void req_untouched(void) { P: x = 1; }

void requires_untouched(void) {
  g = Frama_C_interval(0, 9); x = 0;
  req_untouched();
  g = Frama_C_interval(0, 9); x = 0;
  req_untouched();
}

/* Same, with g read by the body: g is in the key. */
/*@ requires g >= 4; */
void req_read(void) { P: out = g; }

void requires_read(void) {
  g = Frama_C_interval(0, 9); out = 0;
  req_read();
  g = Frama_C_interval(0, 9); out = 0;
  req_read();
}

/* A call with no body-entry state: its start is reachable, every point of
   its body is unreachable. The second call is a hit. */
/*@ requires x > 0; */
void dead(void) { P: g = 2; }

void no_body_entry(void) {
  x = 0; g = 0;
  if (v) dead();
  x = 0; g = 0;
  if (v) dead();
}
