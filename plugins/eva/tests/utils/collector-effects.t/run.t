Leaving an inner scope marks the holder in the output of the body.

  $ frama-c -no-autoload-plugins -load-module eva -eva -eva-no-memexec -main swept -eva-msg-key cache-producer,final-states effects.c > sweep.log 2>&1
  $ grep -o 'collector: would-store; producer: stored (entry 1)' sweep.log
  collector: would-store; producer: stored (entry 1)
  $ grep -o 'locals {local} escaping the scope of a block of swept through holder' sweep.log
  locals {local} escaping the scope of a block of swept through holder

The outer cleanup of a callee is inside its caller's recording.

  $ frama-c -no-autoload-plugins -load-module eva -eva -eva-no-memexec -main foreign_sweep -eva-msg-key cache effects.c > foreign.log 2>&1
  $ grep -o 'call to foreign_sweep: .*collector: refused (sweep)' foreign.log
  call to foreign_sweep: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: refused (sweep)

The recursively analysed body and its enclosing callers refuse.

  $ frama-c -no-autoload-plugins -load-module eva -eva -eva-no-memexec -main start_recursion -eva-unroll-recursive-calls 3 -eva-msg-key cache effects.c > recursive.log 2>&1
  $ grep -o 'call to [a-z_]*: .*collector: refused (recursion)' recursive.log | sed 's/^call to //; s/: .*collector: / /'
  recur refused (recursion)
  recur refused (recursion)
  recur refused (recursion)
  start_recursion refused (recursion)

Threaded mode refuses a body even if it makes no calls.

  $ frama-c -no-autoload-plugins -load-module eva -eva -mthread -eva-no-memexec -main threaded -eva-msg-key cache effects.c > threaded.log 2>&1
  $ grep -o 'collector: refused (threaded)' threaded.log
  collector: refused (threaded)

A dump is an ordered effect. A finite alarm threshold can be reached by an
emission checkpoint with a different number of preceding alarms.

  $ frama-c -no-autoload-plugins -load-module eva -eva -eva-no-memexec -main show -eva-msg-key cache effects.c > dump.log 2>&1
  $ grep -o 'collector: refused (dump)' dump.log
  collector: refused (dump)
  $ frama-c -no-autoload-plugins -load-module eva -eva -eva-no-memexec -main alarm -eva-stop-at-nth-alarm 2 -eva-msg-key cache effects.c > alarm.log 2>&1
  $ grep -o 'collector: refused (stop-at-alarm)' alarm.log
  collector: refused (stop-at-alarm)

A watchpoint's installation and a subsequent body carrying out its checks
both refuse.

  $ frama-c -no-autoload-plugins -load-module eva -eva -eva-no-memexec -main start_watchpoint -eva-msg-key cache effects.c > watch.log 2>&1
  $ grep -o 'call to [a-z_]*: .*collector: refused (watchpoint)' watch.log | sed 's/^call to //; s/: .*collector: / /'
  install_watchpoint refused (watchpoint)
  watched refused (watchpoint)
  start_watchpoint refused (watchpoint)

The observer sees the sweep targets and holder writes. A candidate with the
same projected key refuses when the current input has an additional holder.

  $ dune build -j 8 --cache=disabled --root . test_collector_effects.cmxs
  $ EVA_TEST_COLLECTOR_EFFECTS=sweep frama-c -no-autoload-plugins -load-module eva,test_collector_effects.cmxs -eva-no-memexec -main swept effects.c > replay.log 2>&1
  $ grep -E '^swept records|^unknown-base sweep|rejected=|^producing input|^own outer scope' replay.log
  swept records local and the holder written by its scope exit
  clear rejected=[] hit=1
  offset-range rejected=[1:sweep,2:sweep] hit=none
  garbled rejected=[1:sweep,2:sweep] hit=none
  unknown-bases rejected=[1:sweep,2:sweep] hit=none
  unknown-base sweep keeps all bases and marks escaping
  escaping-plus-pointer rejected=[1:sweep,2:sweep] hit=none
  escaping-marker-alone rejected=[] hit=1
  prebound rejected=[1:key-differs,2:key-differs] hit=none
  producing input clear: clear
  producing input holder: sweep
  producing input prebound: sweep
  own outer scope: sweep
  watch in another project rejected=[1:watchpoint,2:watchpoint] hit=none

A fresh nested call contributes its callees to the enclosing recording.

  $ frama-c -no-autoload-plugins -load-module eva,test_collector_effects.cmxs -eva -eva-no-memexec -main outer effects.c > transitive.log 2>&1
  $ grep '^trace includes' transitive.log
  trace includes the transitive call to threaded

  $ frama-c -no-autoload-plugins -load-module eva,test_collector_effects.cmxs -eva -eva-no-memexec -main start_recursion -eva-unroll-recursive-calls 3 effects.c > recursive-trace.log 2>&1
  $ grep '^trace includes' recursive-trace.log
  trace includes recur and start_recursion

Allocating a trace node is an opaque effect.

  $ frama-c -no-autoload-plugins -load-module eva -eva -eva-no-memexec -eva-domains cvalue,traces -main threaded -eva-msg-key cache effects.c > traces.log 2>&1
  $ grep -o 'collector: refused (trace-id)' traces.log
  collector: refused (trace-id)

The inventory replays use fresh analyses so the observer sees both readers
and both discoverers. In the reader control there is no discovery.

  $ hints () {
  >   frama-c -no-autoload-plugins -load-module eva,test_collector_effects.cmxs \
  >     -eva -eva-no-memexec -eva-slevel 0 -eva-auto-loop-unroll 0 \
  >     -eva-msg-key show "$@"
  > }
  $ hints hint-reader.c > reader.log 2>&1
  $ grep -E '^count generation|^discover |Frama_C_show_each_after:' reader.log
  count generation 0, would-store
  discover widening-hint
  count generation 1, would-store
  [eva:show] hint-reader.c:24: Frama_C_show_each_after: {13}
  $ hints -cpp-extra-args=-DWITHOUT_DISCOVERY hint-reader.c > control.log 2>&1
  $ grep '^count generation' control.log
  count generation 0, would-store
  count generation 0, would-store
  $ hints hint-writer.c > writer.log 2>&1
  $ grep -E '^count_y generation|^discover |Frama_C_show_each_y:' writer.log
  discover widening-hint
  discover widening-hint
  count_y generation 2, would-store
  [eva:show] hint-writer.c:17: Frama_C_show_each_y: {13}

An unclassified log listener runs on a warning inside a body and causes a
callback refusal.

  $ EVA_TEST_COLLECTOR_EFFECTS=logger frama-c -no-autoload-plugins -load-module eva,test_collector_effects.cmxs -eva -eva-no-memexec -main alarm -eva-msg-key cache effects.c > logger.log 2>&1
  $ grep -o 'collector: refused (callback)' logger.log
  collector: refused (callback)

The producing trace of an observed memexec hit carries the transitive call
to the fresh enclosing recording.

  $ frama-c -no-autoload-plugins -load-module eva,inout,test_collector_effects.cmxs -eva -main start_hit -eva-msg-key cache effects.c > hit.log 2>&1
  $ grep -o 'call to middle: lookup: hit (entry [0-9]*)' hit.log
  call to middle: lookup: hit (entry 2)
  $ grep '^trace through memexec hit' hit.log
  trace through memexec hit includes threaded

A discovery of a default threshold refuses without changing the generation.

  $ hints -cpp-extra-args=-DHINT_THRESHOLD=1 hint-reader.c > masked.log 2>&1
  $ grep -E '^count generation|^discover ' masked.log
  count generation 0, would-store
  discover widening-hint
  count generation 0, would-store

Candidate order and exact reasons for a changed generation, a recursive
stack and the same generation number from a different run.

  $ test_effects () {
  >   mode="$1"; shift
  >   EVA_TEST_COLLECTOR_EFFECTS="$mode" frama-c -no-autoload-plugins \
  >     -load-module eva,test_collector_effects.cmxs "$@"
  > }
  $ test_effects hint-lookup -eva-no-memexec -eva-slevel 0 \
  >   -eva-auto-loop-unroll 0 hint-reader.c > lookup.log 2>&1
  $ grep -E 'rejected=|^supplied hit trace|^generation changed' lookup.log
  newer generation rejected=[1:hint-generation] hit=2
  supplied hit trace: count (body), nonrecursive
  recursive stack rejected=[1:recursion,2:recursion] hit=none
  newer run rejected=[1:hint-generation,2:hint-generation,3:hint-generation] hit=4
  supplied hit trace: count (body), nonrecursive
  generation changed in reader: widening-hint

A trace that was nonrecursive when produced can conflict with the caller
that now consumes it.

  $ test_effects trace-stack effects.c > trace-stack.log 2>&1
  $ grep '^included hit trace' trace-stack.log
  included hit trace conflicts with caller: recursion

The watch installation reports its effect before any statement transfer.

  $ test_effects watch-install -eva-no-memexec -main swept effects.c > install.log 2>&1
  $ grep '^watch installation' install.log
  watch installation without statement transfer: watchpoint

A file dump has its own reason and actually writes the first numbered file.

  $ test_effects none -eva -eva-no-memexec -main show_file \
  >   -eva-msg-key cache effects.c > file-dump.log 2>&1
  $ grep -o 'collector: refused (dump)' file-dump.log
  collector: refused (dump)
  $ grep -o 'DUMPING STATE' collector_0
  DUMPING STATE

The red client and the extra history client each execute during a fresh body.
Each body refuses to produce an entry. The history client runs on the
otherwise admitted locals-escaping per-event consultation.

  $ test_effects red-client -eva-no-memexec -main alarm effects.c > red.log 2>&1
  $ grep '^alarm' red.log
  alarm: callback
  alarm client calls: 1, entries: 0
  $ test_effects history-client -eva-no-memexec -main swept effects.c > history.log 2>&1
  $ grep '^swept' history.log
  swept: callback
  swept client calls: 1, entries: 0

Alarm stopping observes changes made by an emission listener with
collection disabled, under both legacy memexec settings.

  $ threshold () {
  >   test_effects raise-threshold -eva -eva-no-cache-collect "$1" \
  >     -main alarm -eva-stop-at-nth-alarm 1 effects.c > threshold.log 2>&1
  > }
  $ threshold -eva-memexec
  $ grep -oE 'listener raised stop threshold|ANALYSIS SUMMARY' threshold.log
  listener raised stop threshold
  ANALYSIS SUMMARY
  $ threshold -eva-no-memexec
  $ grep -oE 'listener raised stop threshold|ANALYSIS SUMMARY' threshold.log
  listener raised stop threshold
  ANALYSIS SUMMARY
