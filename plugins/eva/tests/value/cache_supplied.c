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
*/
/* run.config*
   DONTRUN: the reuse operation with supplied entries needs cvalue alone.
*/

/* Calls answered by the reuse operation from entries supplied by the test
   module cache_supplied.ml. Each body prints its arguments, so that a body
   analysed for a call is visible; a hit prints nothing from the body.
   Expected, in the first run:
   - the first call to step hits entry 1, whose key is {x, g} with x = 1 and
     g = 3: out is 4;
   - after g = 5, the second call to step rejects entry 1 (key-differs) and
     is analysed: out is 6;
   - set_out hits entry 2, whose key is empty and which writes out = 7; keep
     is not written, so it keeps the value 42 of the caller although the
     state supplied as exit binds keep to 0;
   - precise_first hits entry 3, supplied before entry 4: out is 7;
   - wide_first hits entry 5, supplied before entry 6: out is [7..8];
   - no entry is supplied for plain: both calls find no candidate and are
     analysed, and memexec stores nothing. */

int g, out, keep;

void step(int x) {
  Frama_C_show_each_step(x, g);
  out = x + g;
}

void set_out(void) {
  Frama_C_show_each_set_out(keep);
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

int main(void) {
  g = 3;
  step(1);
  Frama_C_show_each_after_hit(out);
  g = 5;
  step(1);
  Frama_C_show_each_after_miss(out);
  keep = 42;
  set_out();
  Frama_C_show_each_after_frame(out, keep);
  precise_first(1);
  Frama_C_show_each_after_precise_first(out);
  wide_first(1);
  Frama_C_show_each_after_wide_first(out);
  plain(1);
  plain(1);
  return 0;
}
