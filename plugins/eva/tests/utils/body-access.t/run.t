The OCaml observer sees whole blocks at the end of the body.

  $ cp ../../../../../dev/collector_statistics.ml .
  $ dune build -j 8 --cache=disabled --root . test_body_access.cmxs collector_statistics.cmxs
  $ frama-c -no-autoload-plugins -load-module eva,test_body_access.cmxs -eva -eva-no-memexec -eva-msg-key cache assignment.c > assignment.log 2>&1
  $ grep -E 'reads p, writes q|; collector:' assignment.log
  reads p, writes q
    call to main: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: would-store

A write before an infinite loop is in W only. Both returning branches
overwrite q. One element of pair is written, and two writes together
overwrite both.

  $ frama-c -no-autoload-plugins -load-module eva,test_body_access.cmxs -eva -eva-no-memexec -main paths paths.c > paths.log 2>&1
  $ grep '^W =' paths.log
  W = both, dead, pair, q; W_exit = both, pair, q; W_sure = both, q

Inout runs its callwise analysis and leaves the collector result unchanged.
Memexec stays disabled in both runs so both executions analyse the body.

  $ frama-c -no-autoload-plugins -load-module eva,inout,test_body_access.cmxs -eva -eva-no-memexec -eva-msg-key cache -eva-statistics-file inout.tsv -input -out assignment.c > inout.log 2>&1
  $ grep 'reads p, writes q' inout.log
  reads p, writes q
  $ grep -o 'storage: refused (disabled); collector: would-store' inout.log
  storage: refused (disabled); collector: would-store
  $ awk -F '\t' '/^(memexec|collector)-/ { print $1, $2, $4 }' inout.tsv
  collector-would-store main 1
  $ grep -A1 '^\[inout\] Inputs for function main:' inout.log
  [inout] Inputs for function main:
      p

Recording can be switched off on the same binary.

  $ frama-c -no-autoload-plugins -load-module eva,inout,test_body_access.cmxs -eva -eva-no-cache-collect -eva-no-memexec -eva-msg-key cache -eva-statistics-file off.tsv assignment.c > off.log 2>&1
  $ grep -Ec 'reads p, writes q|; collector:' off.log
  0
  [1]
  $ grep -c '^collector-' off.tsv
  0
  [1]

Refused observations are delivered to OCaml, including the target of a pointer
copied without dereferencing it. The tests exercise both indirect call sites
and the bodies reached through those sites.

  $ EVA_TEST_BODY_ACCESS=refusals frama-c -no-autoload-plugins -load-module eva,inout,test_body_access.cmxs -eva -eva-no-memexec -eva-msg-key cache -eva-statistics-file refused.tsv refusals.c > refused.log 2>&1
  $ grep -E '^(precondition|contract|annotation|swept|copy|nested|indirect_target|indirect_caller|builtin|main) ' refused.log
  precondition would-store
  contract would-store
  annotation would-store
  swept would-store
  copy allocated-block
  nested nested-call
  indirect_target indirect-call
  indirect_caller indirect-call
  builtin builtin
  main allocation
  $ awk -F '\t' '/^collector-/ { print $1, $2, $4 }' refused.tsv
  collector-refused-allocated-block copy 1
  collector-refused-allocation main 1
  collector-refused-builtin builtin 1
  collector-refused-indirect-call indirect_target 1
  collector-refused-indirect-call indirect_caller 1
  collector-refused-nested-call nested 1
  collector-would-store precondition 1
  collector-would-store contract 1
  collector-would-store annotation 1
  collector-would-store swept 1

The uninitialized binding installed for a volatile local at scope entry is a
possible write, not a sure overwrite. The status of a requires clause of an
inactive behavior is emitted for the call site, outside the body.

  $ frama-c -no-autoload-plugins -load-module eva,test_body_access.cmxs -eva -eva-no-memexec -main volatile_local paths.c > volatile.log 2>&1
  $ grep '^volatile local' volatile.log
  volatile local scope entry is a possible write only
  $ frama-c -no-autoload-plugins -load-module eva,test_body_access.cmxs -eva -eva-no-memexec -main inactive_caller paths.c > inactive.log 2>&1
  $ grep '^inactive behavior' inactive.log
  inactive behavior: requires status outside the body

A call hook with no classification causes a callback refusal.

  $ EVA_TEST_BODY_ACCESS=unknown frama-c -no-autoload-plugins -load-module eva,inout,test_body_access.cmxs -eva -eva-no-memexec -eva-msg-key cache assignment.c > unknown.log 2>&1
  $ grep 'unclassified callback refused' unknown.log
  unclassified callback refused
  $ grep -o 'collector: refused (callback)' unknown.log
  collector: refused (callback)

A cvalue domain restricted by function is outside the collector's admitted
domain, even when the restriction leaves cvalue as the only domain.

  $ EVA_TEST_BODY_ACCESS=restricted frama-c -no-autoload-plugins -load-module eva,inout,test_body_access.cmxs -eva -eva-no-memexec -eva-domains-function cvalue:main- assignment.c > restricted.log 2>&1
  $ grep 'restricted cvalue refused' restricted.log
  restricted cvalue refused

A returning guard reduction changes g. A fresh local binding is also a
possible write. Neither supplies a sure overwrite.

  $ frama-c -no-autoload-plugins -load-module eva,test_body_access.cmxs -eva -eva-no-memexec -lib-entry -main guard paths.c > guard.log 2>&1
  $ grep '^guard reduction' guard.log
  guard reduction contributes possible writes only
  $ frama-c -no-autoload-plugins -load-module eva,test_body_access.cmxs -eva -eva-no-memexec -eva-initialized-locals -main locals paths.c > locals.log 2>&1
  $ grep '^initialized local scope binding' locals.log
  initialized local scope binding contributes a possible write

Merging observations at the graph's vertices loses the correlation between
the first and last tests of b even when Eva partitions the states.

  $ frama-c -no-autoload-plugins -load-module eva,test_body_access.cmxs -eva -eva-no-memexec -lib-entry -main correlated -eva-slevel 20 paths.c > correlated.log 2>&1
  $ grep '^exit graph' correlated.log
  exit graph retains dead across correlated guards

An ordinary division alarm records alarm and status joins.

  $ frama-c -no-autoload-plugins -load-module eva,test_body_access.cmxs -eva -eva-no-memexec -lib-entry -main alarm paths.c > alarm.log 2>&1
  $ grep '^alarm and status' alarm.log
  alarm and status joins recorded

Pointer arithmetic can touch the origin table before any load or store of
the garbled value.

  $ frama-c -no-autoload-plugins -load-module eva,test_body_access.cmxs -eva -eva-no-memexec -main temporary_mix origin.c > origin.log 2>&1
  $ grep '^temporary origin' origin.log
  temporary origin history access refused

Callwise Inout can change the transfers Eva executes in the caller. Here the
actual is reduced after zero returns, pruning the show directive.

  $ EVA_TEST_BODY_ACCESS=inout frama-c -no-autoload-plugins -load-module eva,test_body_access.cmxs -eva -eva-no-memexec -lib-entry -main test inout.c > no-inout.log 2>&1
  $ grep -E 'Frama_C_show_each_g:|^test ' no-inout.log
  [eva:show] inout.c:11: Frama_C_show_each_g: [-2147483648..2147483647]
  test builtin
  $ EVA_TEST_BODY_ACCESS=inout frama-c -no-autoload-plugins -load-module eva,inout,test_body_access.cmxs -eva -eva-no-memexec -lib-entry -main test -input -out inout.c > callwise-inout.log 2>&1
  $ grep -E 'Frama_C_show_each_g:|^test |^\[inout\] Inputs for function test:' callwise-inout.log
  test sweep
  [inout] Inputs for function test:

The first copy has one OCaml observation and one collector verdict. Memexec
answers the second call without another body observation or verdict.

  $ EVA_TEST_BODY_ACCESS=hit frama-c -no-autoload-plugins -load-module eva,inout,test_body_access.cmxs -eva -eva-memexec -eva-msg-key cache -eva-statistics-file hit.tsv hit.c > hit.log 2>&1
  $ grep -E '^copy |call to copy:' hit.log
  copy would-store
    call to copy: lookup: no-candidate; execution: analysed; storage: stored (entry 1); collector: would-store
    call to copy: lookup: hit (entry 1); execution: not-analysed; storage: none
  $ awk -F '\t' '$2 == "copy" && $1 ~ /^(collector-|memexec-hits)/ { print $1, $4 }' hit.tsv
  collector-would-store 1
  memexec-hits 1

Stopping at an alarm unwinds both the interrupted leaf and its caller. The
only observation and count belong to the previously completed body.

  $ EVA_TEST_BODY_ACCESS=interrupted frama-c -no-autoload-plugins -load-module eva,inout,scope,test_body_access.cmxs -eva -eva-stop-at-nth-alarm 1 -eva-msg-key cache -eva-statistics-file interrupted.tsv ../call-cache.t/call-cache.c > interrupted.log 2>&1
  [1]
  $ grep -E '^(completed body|interrupted body recorder)|execution: interrupted' interrupted.log
  completed body: leaf
    call to divide: lookup: no-candidate; execution: interrupted; storage: none
    call to main: lookup: no-candidate; execution: interrupted; storage: none
  interrupted body recorder unwound
  $ awk -F '\t' '/^collector-/ { print $1, $2, $4 }' interrupted.tsv
  collector-would-store leaf 1

Mthread reports intermediate Computed states. The suite observer keeps one
snapshot per analysis, with the same builtin total as the log and final TSV.

  $ mkdir snapshots
  $ cp ../../mthread/mutex.c .
  $ EVA_COLLECTOR_STATS_DIR="$PWD/snapshots" frama-c -no-autoload-plugins -load-module eva,inout,scope,collector_statistics.cmxs -eva -eva-no-memexec -mthread -mt-threads-lib pthreads -eva-slevel 15 -machdep x86_64 -eva-msg-key cache -eva-statistics-file mutex.tsv mutex.c > mutex.log 2>&1
  $ test -s mutex.tsv || cat mutex.log
  $ grep -c 'collector: refused (builtin)' mutex.log
  42
  $ find snapshots -name '*.tsv' | wc -l
  1
  $ cat snapshots/*.status
  completed
  $ awk -F '\t' '$1 == "collector-refused-builtin" { sum[FILENAME] += $4 } END { for (i = 1; i < ARGC; i++) print sum[ARGV[i]] }' snapshots/*.tsv mutex.tsv
  42
  42

Behavior selection and ensures read globals absent from the C body. The
requires clause belongs to the call site. Each run below prints the lines of
the OCaml observer, then the collector verdict of the observed body.

  $ clause () {
  >   name="$1"; shift
  >   EVA_TEST_BODY_ACCESS=annotations frama-c -no-autoload-plugins \
  >     -load-module eva,test_body_access.cmxs -eva -eva-no-memexec \
  >     -eva-msg-key cache -main "$name" annotations.c "$@" \
  >     > "$name.log" 2>&1
  > }
  $ verdict () {
  >   sed -n "s/.*call to $1: .*; collector: \(.*\)/$1 \1/p" "$2"
  > }
  $ clause select_behavior
  $ grep '^selected reads' select_behavior.log
  selected reads post_only, selector
  $ verdict selected select_behavior.log
  selected would-store

Assertions, loop invariants, logic memory primitives and postconditions are
observed through the same collector result. A reduction can narrow a binding
on a returning path without fully overwriting the block.

  $ clause read_assertion
  $ grep '^read_assertion reads' read_assertion.log
  read_assertion reads assertion_only
  $ clause read_invariant -eva-slevel 20
  $ grep '^read_invariant reads' read_invariant.log
  read_invariant reads i, invariant_only
  $ clause read_pointer
  $ grep '^read_pointer reads' read_pointer.log
  read_pointer reads checked
  $ clause read_string
  $ grep '^read_string reads' read_string.log
  read_string reads message, text
  $ clause read_old
  $ grep '^read_old reads' read_old.log
  read_old reads before_only, post_input
  $ clause narrowing -lib-entry
  $ grep '^narrowing reads' narrowing.log
  narrowing reads narrowed

An opaque predicate has no finite read bound. The observer still sees the
body, and the verdict and the statistics identify the clause family.

  $ clause opaque_assertion -eva-statistics-file opaque_assertion.tsv
  $ grep '^opaque_assertion reads' opaque_assertion.log
  opaque_assertion reads Top and refuses annotation
  $ verdict opaque_assertion opaque_assertion.log
  opaque_assertion refused (annotation)
  $ awk -F '\t' '/^collector-/ { print $1, $2, $4 }' opaque_assertion.tsv
  collector-refused-annotation opaque_assertion 1
  $ clause opaque_contract -eva-statistics-file opaque_contract.tsv
  $ grep '^opaque_contract reads' opaque_contract.log
  opaque_contract reads Top and refuses contract
  $ verdict opaque_contract opaque_contract.log
  opaque_contract refused (contract)
  $ awk -F '\t' '/^collector-/ { print $1, $2, $4 }' opaque_contract.tsv
  collector-refused-contract opaque_contract 1

A logic predicate that checks dynamic allocation metadata refuses even on
a static address.

  $ clause allocation_table
  $ grep '^allocation_table refuses' allocation_table.log
  allocation_table refuses side-table

An alarm installed as an assertion by RteGen is evaluated by the body. The
divisor is zero: the assertion is invalid and stops the propagation before
the division, so only the assertion reads the divisor.

  $ EVA_TEST_BODY_ACCESS=annotations frama-c -no-autoload-plugins \
  >   -load-module eva,rtegen,test_body_access.cmxs -main alarm_assertion \
  >   -rte -rte-select alarm_assertion annotations.c \
  >   -then -eva -eva-no-memexec > alarm_assertion.log 2>&1
  $ grep -o "assertion 'rte,division_by_zero' got status invalid.*" \
  >   alarm_assertion.log
  assertion 'rte,division_by_zero' got status invalid (stopping propagation).
  $ grep '^alarm_assertion reads' alarm_assertion.log
  alarm_assertion reads zero_divisor

A validity predicate designates an allocated block without reading it.

  $ clause use_allocated
  $ grep '^valid_pointer designates' use_allocated.log
  valid_pointer designates an allocated block

A load designates the targets of each cell it reads, before Eva combines the
cells. Here a word covers a pointer to an allocated block and an
uninitialized word, so the combined value is uninitialized. The same holds
for a C load, and for a logic load whose location may be invalid.

  $ clause use_logic_word -machdep x86_32
  $ grep '^logic_word designates' use_logic_word.log
  logic_word designates an allocated block
  $ clause use_c_word -machdep x86_32
  $ grep '^c_word designates' use_c_word.log
  c_word designates an allocated block
  $ clause use_logic_or_null -machdep x86_32
  $ grep '^logic_or_null designates' use_logic_or_null.log
  logic_or_null designates an allocated block

A logic value with unknown targets is not a read. The maximum of an empty
range is unspecified: the body reads nothing and designates any block.

  $ clause empty_max
  $ grep '^empty_max refuses' empty_max.log
  empty_max refuses footprint-top, side-table

The freeability of an unknown address is unknown. The analysis completes,
with or without the collector, and the allocation table refuses the body.

  $ clause top_freeable -eva-no-cache-collect
  $ grep -o 'check got status unknown' top_freeable.log
  check got status unknown
  $ clause top_freeable
  $ grep -o 'check got status unknown' top_freeable.log
  check got status unknown
  $ grep '^top_freeable refuses' top_freeable.log
  top_freeable refuses footprint-top, side-table
  $ verdict top_freeable top_freeable.log
  top_freeable refused (footprint-top)

A message that Eva emits once reads the history of emitted messages. The
body refuses as side-table when evaluating a clause emits such a message:
a binding to bottom, an unsupported term, a range bound that cannot be
evaluated, a split on an expression or a predicate that does not separate
the states, and a false postcondition of a specification.

  $ clause let_bottom -eva-reduce-on-logic-alarms
  $ grep -c 'evaluating to bottom' let_bottom.log
  1
  $ grep '^let_bottom refuses' let_bottom.log
  let_bottom refuses side-table
  $ clause let_function
  $ grep '^let_function refuses' let_function.log
  let_function refuses annotation, side-table
  $ clause range_bound
  $ grep '^range_bound refuses' range_bound.log
  range_bound refuses annotation, side-table
  $ clause split_expression
  $ grep -c 'failing to learn perfectly from split' split_expression.log
  1
  $ grep '^split_expression refuses' split_expression.log
  split_expression refuses annotation, side-table
  $ clause split_predicate
  $ grep -c 'failing to learn perfectly from split' split_predicate.log
  1
  $ grep '^split_predicate refuses' split_predicate.log
  split_predicate refuses annotation, side-table
  $ clause call_false_leaf
  $ grep -c 'this postcondition evaluates to false' call_false_leaf.log
  1
  $ grep '^call_false_leaf refuses' call_false_leaf.log
  call_false_leaf refuses contract, nested-call, side-table

A warning category set to `once` disables later messages in that category.
The evaluation of C expressions and partial unrolling also consult the
history for individual events. These accesses refuse as side-table.

  $ clause once_category -eva-warn-key alarm=once
  $ grep -c 'no further messages from category' once_category.log
  1
  $ grep '^once_category refuses' once_category.log
  once_category refuses side-table
  $ clause pointer_comparison -eva-msg-key pointer-comparison
  $ grep -c 'invalid pointer comparison' pointer_comparison.log
  1
  $ grep '^pointer_comparison refuses' pointer_comparison.log
  pointer_comparison refuses side-table
  $ clause partial_unroll -eva-min-loop-unroll 1 \
  >   -eva-warn-key loop-unroll:partial=active
  $ grep -c 'loop not completely unrolled' partial_unroll.log
  1
  $ grep '^partial_unroll refuses' partial_unroll.log
  partial_unroll refuses side-table

The message on an inactive behavior is emitted at level 6 only.

  $ EVA_TEST_BODY_ACCESS=verbose frama-c -no-autoload-plugins \
  >   -load-module eva,test_body_access.cmxs -eva -eva-no-memexec \
  >   -eva-verbose 6 -main inactive_caller paths.c > verbose.log 2>&1
  $ grep -c 'assumes got status invalid; behavior not evaluated' verbose.log
  1
  $ grep '^inactive behavior message' verbose.log
  inactive behavior message refused at level 6

The memory primitives, membership in a set and the comparison of block
addresses read their pointers and the blocks they load. Eva has no read
bound for allocability and freshness.

  $ clause memory_builtins
  $ grep '^memory_builtins reads' memory_builtins.log
  memory_builtins reads block, finite, first, second
  $ clause membership
  $ grep '^membership reads' membership.log
  membership reads member
  $ clause allocable
  $ grep '^allocable refuses' allocable.log
  allocable refuses annotation, side-table
  $ clause fresh
  $ grep '^fresh refuses' fresh.log
  fresh refuses contract, side-table

Eva does not evaluate loop variants, decreases clauses, or global and type
invariants: they add no read.

  $ clause variant
  $ grep '^variant reads' variant.log
  variant reads i
  $ clause decreases_clause
  $ grep '^decreases_clause reads' decreases_clause.log
  decreases_clause reads nothing
  $ clause invariants
  $ grep '^invariants reads' invariants.log
  invariants reads nothing
