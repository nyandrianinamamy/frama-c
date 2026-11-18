The OCaml observer sees whole blocks at the end of the body.

  $ dune build -j 8 --cache=disabled --root . test_body_access.cmxs
  $ frama-c -no-autoload-plugins -load-module eva,test_body_access.cmxs -eva -eva-cache-collect -eva-no-memexec -eva-msg-key cache assignment.c > assignment.log 2>&1
  $ grep -E 'reads p, writes q|; collector:' assignment.log
  reads p, writes q
    call to main: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: would-store

A write before an infinite loop is in W only. Both returning branches
overwrite q. One element of pair is written, and two writes together
overwrite both.

  $ frama-c -no-autoload-plugins -load-module eva,test_body_access.cmxs -eva -eva-cache-collect -eva-no-memexec -main paths paths.c > paths.log 2>&1
  $ grep '^W =' paths.log
  W = both, dead, pair, q; W_exit = both, pair, q; W_sure = both, q

Inout runs its callwise analysis and leaves the collector result unchanged.
Memexec stays disabled in both runs so both executions analyse the body.

  $ frama-c -no-autoload-plugins -load-module eva,inout,test_body_access.cmxs -eva -eva-cache-collect -eva-no-memexec -eva-msg-key cache -eva-statistics-file inout.tsv -input -out assignment.c > inout.log 2>&1
  $ grep 'reads p, writes q' inout.log
  reads p, writes q
  $ grep -o 'storage: refused (disabled); collector: would-store' inout.log
  storage: refused (disabled); collector: would-store
  $ awk -F '\t' '/^(memexec|collector)-/ { print $1, $2, $4 }' inout.tsv
  collector-would-store main 1

Recording can be switched off on the same binary.

  $ frama-c -no-autoload-plugins -load-module eva,inout,test_body_access.cmxs -eva -eva-cache-collect -eva-no-cache-collect -eva-no-memexec -eva-msg-key cache -eva-statistics-file off.tsv assignment.c > off.log 2>&1
  $ grep -Ec 'reads p, writes q|; collector:' off.log
  0
  [1]
  $ grep -c '^collector-' off.tsv
  0
  [1]

Refused observations are delivered to OCaml, including the target of a pointer
copied without dereferencing it. The tests exercise both indirect call sites
and the bodies reached through those sites.

  $ EVA_TEST_BODY_ACCESS=refusals frama-c -no-autoload-plugins -load-module eva,inout,test_body_access.cmxs -eva -eva-cache-collect -eva-no-memexec -eva-msg-key cache -eva-statistics-file refused.tsv refusals.c > refused.log 2>&1
  $ grep -E '^(contract|annotation|swept|copy|nested|indirect_target|indirect_caller|builtin|main) ' refused.log
  contract contract
  annotation annotation
  swept sweep
  copy allocated-block
  nested nested-call
  indirect_target indirect-call
  indirect_caller indirect-call
  builtin builtin
  main builtin
  $ awk -F '\t' '/^collector-/ { print $1, $2, $4 }' refused.tsv
  collector-refused-allocated-block copy 1
  collector-refused-annotation annotation 1
  collector-refused-builtin builtin 1
  collector-refused-builtin main 1
  collector-refused-contract contract 1
  collector-refused-indirect-call indirect_target 1
  collector-refused-indirect-call indirect_caller 1
  collector-refused-nested-call nested 1
  collector-refused-sweep swept 1

A call hook with no classification causes a side-table refusal.

  $ EVA_TEST_BODY_ACCESS=unknown frama-c -no-autoload-plugins -load-module eva,inout,test_body_access.cmxs -eva -eva-cache-collect -eva-no-memexec -eva-msg-key cache assignment.c > unknown.log 2>&1
  $ grep 'unclassified callback refused' unknown.log
  unclassified callback refused
  $ grep -o 'collector: refused (side-table)' unknown.log
  collector: refused (side-table)
