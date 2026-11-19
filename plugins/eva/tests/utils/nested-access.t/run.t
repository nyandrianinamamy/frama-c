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
