/* run.config
   COMMENT: The test module supplies cache entries before it runs the
   COMMENT: analysis, then prints the content of the entries and the counts.
   PLUGIN: eva
   MODULE: @PTEST_NAME@
   OPT: @EVA_OPTIONS@ -eva-msg-key cache
   COMMENT: A product other than cvalue alone rejects every candidate.
   OPT: @EVA_OPTIONS@ -eva-msg-key cache -eva-domains cvalue,sign
   COMMENT: With caching disabled, no cache is consulted.
   OPT: @EVA_OPTIONS@ -eva-msg-key cache -eva-no-memexec
   COMMENT: With Inout loaded, which resolves the identifier of a hit in the
   COMMENT: tables of memexec, every candidate is rejected. Memexec is not
   COMMENT: consulted either: the second call to plain is analysed.
   PLUGIN: eva,inout
   OPT: @EVA_OPTIONS@ -eva-msg-key cache
   COMMENT: So does From, loaded without Inout.
   PLUGIN: eva,from
   OPT: @EVA_OPTIONS@ -eva-msg-key cache
   COMMENT: So does the analysis of threads, which keeps cvalue alone.
   PLUGIN: eva
   OPT: @EVA_OPTIONS@ -eva-msg-key cache -mthread
*/
/* run.config*
   DONTRUN: the reuse operation with supplied entries needs cvalue alone.
*/

/* Calls answered by the reuse operation from entries supplied by the test
   module cache_supplied.ml. Each body but that of twice prints a marker, so
   that a body analysed for a call is visible; a hit prints nothing from the
   body. Expected, in the first run:
   - the first call to step hits entry 1, whose key is {x, g} with x = 1 and
     g = 3: out is 4, g is 3 and keep is 0, as in the exit state of entry 1;
   - after g = 5, the second call to step rejects entry 1 (key-differs) and
     is analysed: out is 6;
   - set_out hits entry 2, whose key is empty and which writes out = 7; keep
     is not written, so it keeps the value 42 of the caller although the
     state supplied as exit binds keep to 0;
   - precise_first hits entry 3, supplied before entry 4: out is 7;
   - wide_first hits entry 5, supplied before entry 6: out is [7..8];
   - no entry is supplied for plain: both calls find no candidate and are
     analysed, and memexec stores nothing;
   - loop_on_4 hits entry 7, whose input has g in {3; 4} and whose exit
     state, that of the path that returns, has g = 3: g is not written, so
     it keeps the value {3; 4} of the caller, and out is 4;
   - write_then_spin hits entry 8: b is written only on a path that loops
     forever and is not in the key; the exit state holds the value 0 of b
     in the input of the producer, and b keeps the value 1 of the caller;
   - never_returns hits entry 9, which has no exit state: the statement
     after the call is not reached;
   - the first call to twice hits entry 10 and returns 6; the second is
     analysed and returns 8;
   - leak_address hits entry 11, whose exit state stores the address of the
     formal x in p: p is escaping after the call.
   The assertions check values after the calls; each one is valid in every
   run. */

volatile int choice;
int g, out, keep, b, r;
int *p;

void step(int x) {
  Frama_C_show_each_step(x, g);
  out = x + g;
}

void set_out(void) {
  Frama_C_show_each_set_out(0);
  out = 7;
}

void precise_first(int x) {
  Frama_C_show_each_precise_first(x);
  out = x + 6;
}

void wide_first(int x) {
  Frama_C_show_each_wide_first(x);
  out = x + 6;
}

void plain(int x) {
  Frama_C_show_each_plain(x);
  out = x;
}

/* Loops forever when g is 4. */
void loop_on_4(int x) {
  Frama_C_show_each_loop_on_4(x, g);
  if (g == 4) for (;;) {}
  out = x + g;
}

/* Writes b and loops forever on one path, returns without writing b on the
   other. */
void write_then_spin(void) {
  Frama_C_show_each_write_then_spin(0);
  if (choice) {
    b = 9;
    for (;;) {}
  }
  out = 5;
}

void never_returns(void) {
  Frama_C_show_each_never_returns(0);
  for (;;) {}
}

int twice(int x) {
  return 2 * x;
}

void leak_address(int x) {
  Frama_C_show_each_leak_address(x);
  p = &x;
}

int main(void) {
  g = 3;
  step(1);
  Frama_C_show_each_after_hit(out, g, keep);
  //@ assert hit_out: out == 4;
  //@ assert hit_g: g == 3;
  //@ assert hit_keep: keep == 0;
  g = 5;
  step(1);
  Frama_C_show_each_after_miss(out);
  //@ assert miss: out == 6;
  keep = 42;
  set_out();
  Frama_C_show_each_after_frame(out, keep);
  //@ assert written: out == 7;
  //@ assert kept: keep == 42;
  precise_first(1);
  Frama_C_show_each_after_precise_first(out);
  //@ assert older: out == 7;
  wide_first(1);
  Frama_C_show_each_after_wide_first(out);
  plain(1);
  plain(1);
  g = choice ? 3 : 4;
  loop_on_4(1);
  Frama_C_show_each_after_loop_on_4(out, g);
  //@ assert loop_out: out == 4;
  b = 1;
  write_then_spin();
  Frama_C_show_each_after_write_then_spin(out, b);
  //@ assert spin_out: out == 5;
  //@ assert spin_b: b == 1;
  if (choice) {
    never_returns();
    Frama_C_show_each_unreachable(0);
  }
  r = twice(3);
  //@ assert returned: r == 6;
  r = twice(4);
  //@ assert analysed: r == 8;
  leak_address(1);
  //@ assert escaping: \dangling(&p);
  return 0;
}
