The observer checks the enclosing record before storage on a fresh call.
Both x and payload are read. The entry key contains only payload because
every path to the call first overwrites x.

  $ dune build -j 8 --cache=disabled --root . test_nested_access.cmxs
  $ EVA_TEST_NESTED_ACCESS=fresh frama-c -no-autoload-plugins -load-module eva,test_nested_access.cmxs -eva -eva-no-memexec nested.c > fresh.log 2>&1
  $ grep -E '^(outer:|stored outer key:)' fresh.log
  outer: reads payload,x; depends on payload; writes out,x; recorded guards and child reference
  stored outer key: payload

Supply both entries from the fresh analysis, in order. The first one
writes rejected_only and must contribute nothing to outer. The observer
checks the same sets on the hit and the identity of the selected child.

  $ EVA_TEST_NESTED_ACCESS=replay frama-c -no-autoload-plugins -load-module eva,test_nested_access.cmxs -eva-msg-key cache nested.c > replay.log 2>&1
  $ grep -E '^(outer:|stored outer key:|confirmed|  call to child: lookup: .*rejected)' replay.log
  outer: reads payload,x; depends on payload; writes out,x; recorded guards and child reference
  stored outer key: payload
    call to child: lookup: rejected (entry 1: key-differs), hit (entry 2); execution: not-analysed; storage: none
  outer: reads payload,x; depends on payload; writes out,x; recorded guards and child reference
  stored outer key: payload
  confirmed two child hits, one after a rejected candidate

A fresh intermediate body has no entry because of its requires clause.
Its child's reference survives in the enclosing entry.

  $ frama-c -no-autoload-plugins -load-module eva,test_nested_access.cmxs -eva -eva-no-memexec -main inline_parent nested.c > inline.log 2>&1
  $ grep '^inline_parent:' inline.log
  inline_parent: retained child at the two-statement call path

A child analysed by specification contributes its behavior-selection reads,
assigns and from dependencies, and the read of the result of the weak
update during the garbled-mix check.

  $ frama-c -no-autoload-plugins -load-module eva,test_nested_access.cmxs -eva -eva-no-memexec -eva-verbose 2 -main spec_parent nested.c > spec.log 2>&1
  $ grep '^spec_parent:' spec.log
  spec_parent: reads destination,selector,source; may write destination; recorded statuses inline

A fresh child frees a live block and its enclosing body inherits the
deallocation refusal.

  $ frama-c -no-autoload-plugins -load-module eva,test_nested_access.cmxs -eva -eva-no-memexec -main free_main -eva-msg-key cache nested.c > free.log 2>&1
  $ grep -E '^(release|free_parent) refused|call to free_parent:' free.log
  release refused deallocation
  free_parent refused deallocation
    call to free_parent: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: refused (deallocation)

An optional overwrite does not eliminate an entry dependency. The
callee's formal is covered by the footprint, and its value comes from
the actual argument.

  $ frama-c -no-autoload-plugins -load-module eva,test_nested_access.cmxs -eva -eva-no-memexec -lib-entry -main maybe_overwrite nested.c > maybe.log 2>&1
  $ grep '^maybe_overwrite:' maybe.log
  maybe_overwrite: x is still an entry dependency
  $ frama-c -no-autoload-plugins -load-module eva,test_nested_access.cmxs -eva -eva-no-memexec -eva-verbose 2 -main formal_parent nested.c > formal.log 2>&1
  $ grep '^formal_parent:' formal.log
  formal_parent: local is in the prefix footprint; formal_in supplies its value

A child with no exit still contributes its prefix reads and writes.

  $ frama-c -no-autoload-plugins -load-module eva,test_nested_access.cmxs -eva -eva-no-memexec -main prefix_parent nested.c > prefix.log 2>&1
  $ grep '^prefix_parent:' prefix.log
  prefix_parent: prefix_input and prefix_out are covered even without an exit

An enclosing hit would skip nested cleanup. The registry was empty in the
producer. It contains an automatic block in the consumer, so the
enclosing candidate is rejected.

  $ EVA_TEST_NESTED_ACCESS=automatic frama-c -no-autoload-plugins -load-module eva,test_nested_access.cmxs -eva-msg-key cache nested.c > automatic.log 2>&1
  $ grep 'call to outer: lookup: rejected' automatic.log
    call to outer: lookup: rejected (entry 1: automatic-cleanup); execution: analysed; storage: refused (supplied-only); collector: would-store

A child of the enclosing entry is on the current callstack. The entry
would skip a recursive call from the enclosing body, so it is rejected.

  $ EVA_TEST_NESTED_ACCESS=recursive frama-c -no-autoload-plugins -load-module eva,test_nested_access.cmxs -eva-msg-key cache nested.c > recursive.log 2>&1
  $ grep -o 'call to outer: lookup: rejected (entry 1: recursion); execution: analysed' recursive.log
  call to outer: lookup: rejected (entry 1: recursion); execution: analysed


The split return makes the destination x on one returned state and y on
the other. Pin the collector result and key separately from lookup.
Compare the final value and alarm with caching disabled in each case.

  $ fc() { frama-c -no-autoload-plugins -load-module eva,test_nested_access.cmxs -eva "$@"; }
  $ split() { fc -eva-slevel 20 -eva-split-return-function pick:full "$@"; }
  $ outcome() { sed -n -e 's/^.*Frama_C_show_each: /Frama_C_show_each: /p' -e 's/^ *1 division by zero$/1 division by zero/p' "$1" | tail -2; }
  $ split -eva-no-memexec -main second split_fresh.c > fresh-off.log 2>&1
  $ EVA_TEST_NESTED_ACCESS=split-fresh split -eva-msg-key cache split_fresh.c > split-fresh.log 2>&1
  $ grep -E '^f:|^stored f key:|call to f: lookup: rejected' split-fresh.log
  f: x,y are possible writes and entry dependencies; only out is sure
  stored f key: p,x,y
  f: x,y are possible writes and entry dependencies; only out is sure
    call to f: lookup: rejected (entry 1: key-differs); execution: analysed; storage: refused (supplied-only); collector: would-store
  $ outcome fresh-off.log > expected
  $ outcome split-fresh.log > actual
  $ diff expected actual
  $ cat actual
  Frama_C_show_each: {1; 10}, {2; 20}, {12; 21}
  1 division by zero

The supplied pick takes the same split-return path through the caller.
The independently recorded f key must still include both incoming values.

  $ split -eva-no-memexec -main second split_supplied.c > supplied-off.log 2>&1
  $ EVA_TEST_NESTED_ACCESS=split-supplied split -eva-msg-key cache split_supplied.c > split-supplied.log 2>&1
  $ grep -E '^stored f key:|^confirmed supplied pick|call to pick: lookup: hit|call to f: lookup: rejected' split-supplied.log
  stored f key: p,x,y
    call to pick: lookup: hit (entry 1); execution: not-analysed; storage: none
  stored f key: p,x,y
  confirmed supplied pick hit before observing f
    call to f: lookup: rejected (entry 2: key-differs); execution: analysed; storage: refused (supplied-only); collector: would-store
  $ outcome supplied-off.log > expected
  $ outcome split-supplied.log > actual
  $ diff expected actual
  $ cat actual
  Frama_C_show_each: {1; 10}, {2; 20}, {12; 21}
  1 division by zero

In one main, the first f matches the supplied entry's key. Its nested
work cannot be delivered yet. The second f has a different key.

  $ split -eva-no-memexec split_same.c > same-off.log 2>&1
  $ EVA_TEST_NESTED_ACCESS=split-same split -eva-msg-key cache split_same.c > split-same.log 2>&1
  $ grep -E 'call to f: lookup: rejected' split-same.log
    call to f: lookup: rejected (entry 1: nested-delivery); execution: analysed; storage: refused (supplied-only); collector: would-store
    call to f: lookup: rejected (entry 1: key-differs); execution: analysed; storage: refused (supplied-only); collector: would-store
  $ outcome same-off.log > expected
  $ outcome split-same.log > actual
  $ diff expected actual
  $ cat actual
  Frama_C_show_each: {1; 10}, {2; 20}, {12; 21}
  1 division by zero

Check the logger consultation for explicit empty allocation clauses,
including the clause of an inactive behavior.

  $ EVA_TEST_NESTED_ACCESS=history fc -eva-no-memexec history.c > history.log 2>&1
  $ grep -oE 'ignoring unsupported allocates clause|allocation clause: side-table before storage' history.log
  ignoring unsupported allocates clause
  allocation clause: side-table before storage
  $ EVA_TEST_NESTED_ACCESS=history fc -eva-no-memexec -main inactive_main history.c > inactive.log 2>&1
  $ grep -oE 'ignoring unsupported allocates clause|allocation clause: side-table before storage' inactive.log
  ignoring unsupported allocates clause
  allocation clause: side-table before storage

An enclosing hit cannot yet deliver the child's assertion. Reject it and
check that Eva gives the same invalid assertion status as caching off.

  $ fc -eva-no-memexec -eva-debug 1 -eva-warn-key alarm=inactive -main second status.c > status-off.log 2>&1
  $ EVA_TEST_NESTED_ACCESS=status fc -eva-msg-key cache -eva-debug 1 -eva-warn-key alarm=inactive status.c > status.log 2>&1
  $ grep 'call to f: lookup: rejected' status.log
    call to f: lookup: rejected (entry 1: nested-delivery); execution: analysed; storage: refused (supplied-only); collector: would-store
  $ grep -E 'Assertions +0 valid +0 unknown +1 invalid +1 total' status-off.log > expected
  $ grep -E 'Assertions +0 valid +0 unknown +1 invalid +1 total' status.log | tail -1 > actual
  $ diff expected actual
  $ grep -c 'Marking property Assertion .* as dead' status.log || true
  0

A full state dump reports a conservative read bound before storage.

  $ EVA_TEST_NESTED_ACCESS=dump fc -eva-no-memexec dump.c > dump.log 2>&1
  $ sed -n '/Frama_C_dump_each:/,/END OF DUMP/{/x ∈/p;}; /^dump: Top/p' dump.log
    x ∈ {9}
  dump: Top reads and dependencies before storage

Produce mid, supply it during production of f, then supply f with g
active. Check mid's transitive contribution at the supplied-hit seam
while the lookup guard prevents hits of mid in this program.

  $ EVA_TEST_NESTED_ACCESS=guard fc -eva-msg-key cache guard.c > guard.log 2>&1
  $ grep -E '^supplied mid|call to (mid|f): lookup: rejected' guard.log
  supplied mid observation contributes transitive g
    call to mid: lookup: rejected (entry 1: nested-delivery); execution: analysed; storage: refused (supplied-only); collector: would-store
    call to f: lookup: rejected (entry 2: recursion); execution: analysed; storage: refused (supplied-only); collector: refused (recursion)


A lexical sweep admitted for the child is foreign to the enclosing body,
including when the child is answered by a supplied hit.

  $ EVA_TEST_NESTED_ACCESS=sweep fc -main sweep_main -eva-msg-key cache nested.c > sweep.log 2>&1
  $ grep -E '^sweep_parent:|call to own_sweep: lookup: hit' sweep.log
  sweep_parent: child's lexical sweep is foreign
    call to own_sweep: lookup: hit (entry 1); execution: not-analysed; storage: none
  sweep_parent: child's lexical sweep is foreign

The supplied child must use a hint stamp from the current run. Supply it
at the marker after the fresh child has run in that analysis.

  $ EVA_TEST_NESTED_ACCESS=hints fc -main hint_main -eva-slevel 0 -eva-auto-loop-unroll 0 -eva-msg-key cache nested.c > hints.log 2>&1
  $ grep -E '^hint_parent:|call to hint_reader: lookup: hit' hints.log
  hint_parent: hint generation 0
  hint_parent: hint generation 0
  hint_parent: hint generation 0
    call to hint_reader: lookup: hit (entry 2); execution: not-analysed; storage: none
  hint_parent: hint generation 0


An inline specification has no child entry of its own. Its recorded
invocation still requires delivery before the enclosing body can hit.

  $ EVA_TEST_NESTED_ACCESS=inline fc -main spec_parent -eva-verbose 2 -eva-msg-key cache nested.c > inline-spec.log 2>&1
  $ grep -o 'call to spec_parent: lookup: rejected (entry 1: nested-delivery); execution: analysed' inline-spec.log
  call to spec_parent: lookup: rejected (entry 1: nested-delivery); execution: analysed
