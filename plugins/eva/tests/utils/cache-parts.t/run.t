Parts of cache entries owned by From and Inout. In each scenario, a first
analysis with caching disabled produces the entries of the callees of
parts.c, which are then supplied to a second analysis. The test module
prints the parts of each entry and compares the two analyses.

  $ dune build -j 8 --cache=disabled --root . test_cache_parts.cmxs test_cache_parts_server.cmxs test_cache_parts_readers.cmxs

With -calldeps, each entry has a From part and an Inout part. The three
calls to copy hit in the second analysis. The callwise dependencies of every
call site are those of the first analysis: at the call sites of copy, which
the hits restore, and at that of deps_main, which joins them.

  $ EVA_TEST_CACHE_PARTS=from frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -calldeps parts.c > from.log 2>&1
  $ grep -E '^(entry of|hits|callwise|copy at|deps_main at)' from.log
  entry of copy: parts [from, inout]
  entry of copy: parts [from, inout]
  entry of copy: parts [from, inout]
  entry of narrow: parts [from, inout]
  entry of narrow_and_write: parts [from, inout]
  entry of checked: parts [from, inout]
  entry of checked: parts [from, inout]
  hits: copy 3
  callwise dependencies equal at 10 call sites: true
  copy at line 38: a FROM indirect: dst; src; direct: b; \result FROM \nothing
  copy at line 39: c FROM indirect: dst; src; direct: d; \result FROM \nothing
  copy at line 40: a FROM indirect: dst; src; direct: b; \result FROM \nothing
  deps_main at line 53: a FROM direct: b; c FROM direct: d; \result FROM \nothing

From prints no feedback for a call answered by a hit, as at a hit of
memexec: 2 lines from the analysis that -calldeps starts, whose third call
to copy is a hit of memexec, 3 from the analysis with caching disabled, and
none from the analysis with the three hits.

  $ grep -c 'Computing for function copy' from.log
  5

With Inout alone, each entry has an Inout part. After the hits on narrow and
narrow_and_write, the caller reduces its actual g, which the callee does not
write, and does not reduce h, which the callee writes, as with caching
disabled. The callwise inputs and outputs of every call site, and those of
every function joined over its calls, are those of the first analysis.

  $ EVA_TEST_CACHE_PARTS=inout frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > inout.log 2>&1
  $ grep -E '^(entry of|hits|caching disabled|after the hits|callwise|inputs)' inout.log
  entry of copy: parts [inout]
  entry of copy: parts [inout]
  entry of copy: parts [inout]
  entry of narrow: parts [inout]
  entry of narrow_and_write: parts [inout]
  entry of checked: parts [inout]
  entry of checked: parts [inout]
  caching disabled: g after narrow {5}, h after narrow_and_write {7}
  hits: narrow 1, narrow_and_write 1
  after the hits: g after narrow {5}, h after narrow_and_write {7}
  callwise inputs and outputs equal at 9 call sites: true
  inputs and outputs equal for 7 functions: true

A premise of the supplier, violated here on purpose: the options of Eva are
the same in the analysis that produces the entries and in the one that uses
them. With -eva-no-results-function narrow in the using analysis only, the
caller does not reduce g with caching disabled, and reduces it after the
hit, which restores the Inout part of the producing analysis. Nothing
detects the difference.

  $ EVA_TEST_CACHE_PARTS=options frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > options.log 2>&1
  $ grep -E '^options differ' options.log
  options differ: g after narrow: caching disabled {-5; 5}; after 1 hit {5}

A body visited several times in one analysis. In visits.c, the third call
to choose hits the entry produced by the first call, before the second call
reached the other branch; with caching disabled, it is analysed after both
branches were reached. Its callwise dependencies are the same in the three
analyses. The last three dispositions are those of the analysis with the
supplied entries.

  $ EVA_TEST_CACHE_PARTS=visits frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -calldeps -eva-msg-key cache visits.c > visits.log 2>&1
  $ grep -E '^(memexec hits|caching disabled|memexec:|supplied hits:|equal)' visits.log
  memexec hits: choose 1; supplied hits: choose 3
  caching disabled: choose at line 16: a FROM indirect: c; direct: b; \result FROM \nothing
  caching disabled: choose at line 17: a FROM indirect: c; direct: d; \result FROM \nothing
  caching disabled: choose at line 18: a FROM indirect: c; direct: b; \result FROM \nothing
  memexec: choose at line 16: a FROM indirect: c; direct: b; \result FROM \nothing
  memexec: choose at line 17: a FROM indirect: c; direct: d; \result FROM \nothing
  memexec: choose at line 18: a FROM indirect: c; direct: b; \result FROM \nothing
  supplied hits: choose at line 16: a FROM indirect: c; direct: b; \result FROM \nothing
  supplied hits: choose at line 17: a FROM indirect: c; direct: d; \result FROM \nothing
  supplied hits: choose at line 18: a FROM indirect: c; direct: b; \result FROM \nothing
  equal to caching disabled: true; equal to memexec: true
  $ grep -o 'call to choose: lookup: [^;]*; execution: [a-z-]*' visits.log | tail -3
  call to choose: lookup: hit (entry 1); execution: not-analysed
  call to choose: lookup: rejected (entry 1: key-differs), hit (entry 2); execution: not-analysed
  call to choose: lookup: hit (entry 1); execution: not-analysed

The results of the analysis that From and Inout ask while it runs. In
history.c, the first and third calls to leaf do not reach the branch that
the second call reaches. At the end of each call, the results of the
analysis answer that the statements this call does not reach are
reachable, and give Top as the state at the start of leaf, which the
assertion reads at the label Pre: the answers do not depend on the other
calls. The assertion also reads the initial state at the label Init: the
entries keep their Inout part, which a label without a state would
withhold. In the second analysis, the first and third calls hit the entry
of the first call, and the results of From and Inout at each call are
those of caching disabled.

  $ EVA_TEST_CACHE_PARTS=history frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -calldeps history.c > history.log 2>&1
  $ grep -E '^(call of leaf|entry of|hits|leaf at)' history.log
  call of leaf: statements not reached 2, reachable in the results 2; state at the start: top true
  call of leaf: statements not reached 0, reachable in the results 0; state at the start: top true
  call of leaf: statements not reached 2, reachable in the results 2; state at the start: top true
  entry of leaf: parts [from, inout]
  entry of leaf: parts [from, inout]
  entry of leaf: parts [from, inout]
  hits: leaf 2
  leaf at line 23: z FROM \nothing; \result FROM \nothing; equal to caching disabled: dependencies true, inputs and outputs true
  leaf at line 24: x FROM indirect: c; direct: a; y FROM indirect: c; z FROM \nothing; \result FROM \nothing; equal to caching disabled: dependencies true, inputs and outputs true
  leaf at line 25: z FROM \nothing; \result FROM \nothing; equal to caching disabled: dependencies true, inputs and outputs true

With -eva, Eva also analyses the program before the test module does, and
prints the final states after each of the three analyses, filtered by the
outputs that Inout computes by function. After the analysis with hits,
Inout refuses these outputs: Eva prints the final states without filtering
them, as when Inout is not loaded. An analysed caller of a hit has the same
values as with caching disabled. The states saved at the statements of a
function do not cover its calls answered by hits: in place of its final
state, Eva prints that the values are incomplete, with the number of these
calls.

  $ EVA_TEST_CACHE_PARTS=inout frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -eva parts.c > display.log 2>&1
  $ grep -o 'Values at end of function [a-z_]*' display.log | sort | uniq -c
        3 Values at end of function checked
        3 Values at end of function copy
        3 Values at end of function deps_main
        3 Values at end of function inout_main
        3 Values at end of function main
        3 Values at end of function narrow
        3 Values at end of function narrow_and_write
  $ grep -A1 'Values at end of function' display.log | grep -B1 incomplete | sed 's/^\[eva:final-states\] //'
  Values at end of function checked:
    incomplete: 2 calls answered by the cache, without a state at the statements of the function
  Values at end of function copy:
    incomplete: 3 calls answered by the cache, without a state at the statements of the function
  --
  Values at end of function narrow:
    incomplete: 1 call answered by the cache, without a state at the statements of the function
  Values at end of function narrow_and_write:
    incomplete: 1 call answered by the cache, without a state at the statements of the function
  $ grep -B1 'Cannot filter' display.log | grep -o 'Values at end of function [a-z_]*'
  Values at end of function deps_main
  Values at end of function inout_main
  Values at end of function main
  $ awk '/Values at end of function/ { f = /inout_main/ } f && /^ +(g|h|out) /' display.log
    g ∈ {5}
    h ∈ {7}
    out ∈ {5}
    g ∈ {5}
    h ∈ {7}
    out ∈ {5}
    g ∈ {5}
    h ∈ {7}
    out ∈ {5}

The same printer under the options that decide which states are saved, set
in the analysis that produces the entries (producer), in the one that uses
them (consumer) or in both: -eva-no-results (results),
-eva-no-results-function copy (function) and -eva-no-results-domain cvalue
(domain). Each line gives the hits on copy, then what Eva prints for copy
after an analysis with caching disabled and the options of the using
analysis, and after the using analysis. With the option in both analyses or
in the using one alone, the states of copy are not saved: copy hits, and
Eva prints nothing for it in either analysis. With the option in the
producing analysis alone, under results and function the entries of copy
have no points, the using analysis needs them, and every candidate is
rejected (missing-points): copy is analysed and its values are those of
caching disabled. Under domain, the producing analysis records the points,
copy hits, and Eva prints that its values are incomplete. No line prints a
value of copy that caching disabled does not print.

  $ copy_values() { awk '/Values at end of function/ { f = /function copy/ } f && /^ +(a|c) |incomplete/' | tr -s ' \n' ' '; }
  $ for o in results function domain; do for w in producer consumer both; do EVA_TEST_CACHE_PARTS=saved-states EVA_TEST_CACHE_PARTS_OPTION=$o EVA_TEST_CACHE_PARTS_WHERE=$w frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -eva parts.c > saved-$o-$w.log 2>&1; sed -n '/^caching disabled/,/^producing analysis/p' saved-$o-$w.log > disabled.txt; sed -n '/^using analysis/,$p' saved-$o-$w.log > using.txt; echo "$o, $w: $(grep '^hits' saved-$o-$w.log); caching disabled: [$(copy_values < disabled.txt)]; using: [$(copy_values < using.txt)]"; done; done
  results, producer: hits: copy 0, rejected for missing-points 5; caching disabled: [ a ∈ {1} c ∈ {0; 2} ]; using: [ a ∈ {1} c ∈ {0; 2} ]
  results, consumer: hits: copy 3, rejected for missing-points 0; caching disabled: []; using: []
  results, both: hits: copy 3, rejected for missing-points 0; caching disabled: []; using: []
  function, producer: hits: copy 0, rejected for missing-points 5; caching disabled: [ a ∈ {1} c ∈ {0; 2} ]; using: [ a ∈ {1} c ∈ {0; 2} ]
  function, consumer: hits: copy 3, rejected for missing-points 0; caching disabled: []; using: []
  function, both: hits: copy 3, rejected for missing-points 0; caching disabled: []; using: []
  domain, producer: hits: copy 3, rejected for missing-points 0; caching disabled: [ a ∈ {1} c ∈ {0; 2} ]; using: [ incomplete: 3 calls answered by the cache, without a state at the statements of the function ]
  domain, consumer: hits: copy 3, rejected for missing-points 0; caching disabled: []; using: []
  domain, both: hits: copy 3, rejected for missing-points 0; caching disabled: []; using: []

-calldeps is set only after the first analysis: the entries have no From
part. In the second analysis, every candidate whose key matches is rejected
(missing-part) and the bodies are analysed, which records their callwise
dependencies.

  $ EVA_TEST_CACHE_PARTS=missing frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -eva-msg-key cache parts.c > missing.log 2>&1
  $ grep -E '^([a-z_]+: hits|copy at)' missing.log
  copy: hits 0, rejected for missing-part 5
  narrow: hits 0, rejected for missing-part 1
  narrow_and_write: hits 0, rejected for missing-part 1
  checked: hits 0, rejected for missing-part 4
  copy at line 38: a FROM indirect: dst; src; direct: b; \result FROM \nothing
  copy at line 39: c FROM indirect: dst; src; direct: d; \result FROM \nothing
  copy at line 40: a FROM indirect: dst; src; direct: b; \result FROM \nothing
  $ grep -o 'call to copy: lookup: rejected[^;]*; execution: [a-z-]*' missing.log
  call to copy: lookup: rejected (entry 1: missing-part), rejected (entry 2: key-differs), rejected (entry 3: missing-part); execution: analysed
  call to copy: lookup: rejected (entry 1: key-differs), rejected (entry 2: missing-part), rejected (entry 3: key-differs); execution: analysed
  call to copy: lookup: rejected (entry 1: missing-part), rejected (entry 2: key-differs), rejected (entry 3: missing-part); execution: analysed

Each entry of copy is supplied again by hand, without its Reach part and
without the parts of other modules. Inout is loaded and needs its part:
each candidate whose key matches lacks both, and the lookup rejects it with
missing-part, which it tests before missing-points.

  $ EVA_TEST_CACHE_PARTS=both frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -eva-msg-key cache parts.c > both.log 2>&1
  $ grep -E '^copy: hits' both.log
  copy: hits 0, rejected for missing-part 5, for missing-points 0
  $ grep -o 'call to copy: lookup: rejected[^;]*; execution: [a-z-]*' both.log
  call to copy: lookup: rejected (entry 1: missing-part), rejected (entry 2: key-differs), rejected (entry 3: missing-part); execution: analysed
  call to copy: lookup: rejected (entry 1: key-differs), rejected (entry 2: missing-part), rejected (entry 3: key-differs); execution: analysed
  call to copy: lookup: rejected (entry 1: missing-part), rejected (entry 2: key-differs), rejected (entry 3: missing-part); execution: analysed

A body with a call. In nested.c, outer calls inner: the entries of inner
have both parts, those of outer have none. In the second analysis, the
calls to inner hit, every candidate of outer is rejected for missing-part,
and the callwise dependencies are those of caching disabled. The function
unused is never called: Inout computes its inputs and outputs from the
states saved at its statements, which it refuses after the hits. The last
two dispositions are those of the analysis with the supplied entries: the
entry whose key matches is rejected for missing-part.

  $ EVA_TEST_CACHE_PARTS=nested frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -calldeps -eva-msg-key cache nested.c > nested.log 2>&1
  $ grep -E '^(entry of|inner:|callwise|caching disabled:|after the hits:)' nested.log
  entry of inner: parts [from, inout]
  entry of inner: parts [from, inout]
  entry of outer: parts []
  entry of outer: parts []
  caching disabled: Inout.get_precise_inout of unused: computed
  inner: hits 2; outer: hits 0, rejected for missing-part 2
  callwise dependencies equal at 4 call sites: true
  after the hits: Inout.get_precise_inout of unused: refused
  $ grep -o 'call to outer: lookup: [^;]*; execution: [a-z-]*' nested.log | tail -2
  call to outer: lookup: rejected (entry 3: missing-part), rejected (entry 4: key-differs); execution: analysed
  call to outer: lookup: rejected (entry 3: key-differs), rejected (entry 4: missing-part); execution: analysed

A body whose only call is under a condition that the producing call did not
meet. In dead-call.c, leaf(0) does not call other: From and Inout give
their parts, which concern the calls recorded, and the entry of leaf has
both. The lookup rejects it (nested-delivery), since the body has a call,
and the body is analysed.

  $ EVA_TEST_CACHE_PARTS=dead-call frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -calldeps -eva-msg-key cache dead-call.c > dead-call.log 2>&1
  $ grep -E '^(entry of|leaf:|callwise)' dead-call.log
  entry of leaf: parts [from, inout]
  leaf: hits 0, rejected for nested-delivery 1
  callwise dependencies equal at 2 call sites: true
  $ grep -o 'call to leaf: lookup: [^;]*; execution: [a-z-]*' dead-call.log | tail -1
  call to leaf: lookup: rejected (entry 1: nested-delivery); execution: analysed

With -from-verify-assigns, the clauses of checked are checked in the first
analysis. Their statuses are then removed. A hit evaluates no clause: under
this option the part of From is not audited, both calls to checked reject
their candidates in the second analysis (callback), and the analysis of the
body checks the clauses again.

  $ EVA_TEST_CACHE_PARTS=verify frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -from-verify-assigns parts.c > verify.log 2>&1
  $ grep -E '^(caching disabled|statuses removed|checked|second analysis)' verify.log
  caching disabled: assigns clause in function checked: VALID according to Eva
  caching disabled: from clause of term vout in function checked: VALID according to Eva
  statuses removed: assigns clause in function checked: no verification attempted
  statuses removed: from clause of term vout in function checked: no verification attempted
  checked: hits 0, rejected for callback 4
  second analysis: assigns clause in function checked: VALID according to Eva
  second analysis: from clause of term vout in function checked: VALID according to Eva

An assertion that Eva does not evaluate, tagged no_eva, whose logic inputs
Inout computes from the address in p. Eva does not read p: an entry
produced at a call with p = &a would match a call with p = &b. The Inout
part of each entry of leaf is withheld (uncovered-read), every candidate is
rejected (missing-part) and the body is analysed: the logic inputs at each
call site are those of caching disabled. In logic.c, leaf is called at two
sites of main and through wrap; in logic_loop.c, twice at one call site; in
logic_wider.c, first with an address among two, then with one of them.
Without the check, the restored logic inputs miss a block that caching
disabled finds in the first three runs. In the last run, without
-eva-slevel, the first call of logic_wider.c is analysed with p pointing to
a or b, and its entry matches the second call, with p = &a: the restored
logic inputs would be wider than with caching disabled.

  $ EVA_TEST_CACHE_PARTS=logic frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -calldeps -eva-slevel 20 -eva-msg-key cache,cache-producer logic.c > logic.log 2>&1
  $ grep -E '^(entry of|leaf|logic inputs)' logic.log
  entry of leaf: parts [from]
  entry of leaf: parts [from]
  entry of leaf: parts [from]
  leaf: hits 0, rejected for missing-part 9
  leaf at line 14: logic inputs b; p; caching disabled b; p
  leaf at line 18: logic inputs a; p; caching disabled a; p
  leaf at line 20: logic inputs b; p; caching disabled b; p
  logic inputs equal to caching disabled: true
  $ grep -o 'call to leaf: lookup: [^;]*; execution: [a-z-]*' logic.log | tail -3
  call to leaf: lookup: rejected (entry 1: missing-part), rejected (entry 2: missing-part), rejected (entry 3: missing-part); execution: analysed
  call to leaf: lookup: rejected (entry 1: missing-part), rejected (entry 2: missing-part), rejected (entry 3: missing-part); execution: analysed
  call to leaf: lookup: rejected (entry 1: missing-part), rejected (entry 2: missing-part), rejected (entry 3: missing-part); execution: analysed
  $ grep -o 'producer: stored (entry [0-9]*; withheld: [a-z, ]* ([a-z-]*))' logic.log | sort | uniq -c
        3 producer: stored (entry 1; withheld: inout (uncovered-read))
        3 producer: stored (entry 2; withheld: inout (uncovered-read))
        2 producer: stored (entry 3; withheld: inout (uncovered-read))
  $ EVA_TEST_CACHE_PARTS=logic frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -calldeps -eva-slevel 20 -eva-msg-key cache logic_loop.c > logic_loop.log 2>&1
  $ grep -E '^(entry of|leaf|logic inputs)' logic_loop.log
  entry of leaf: parts [from]
  entry of leaf: parts [from]
  leaf: hits 0, rejected for missing-part 4
  leaf at line 16: logic inputs a; b; p; caching disabled a; b; p
  logic inputs equal to caching disabled: true
  $ grep -o 'call to leaf: lookup: [^;]*; execution: [a-z-]*' logic_loop.log | tail -2
  call to leaf: lookup: rejected (entry 1: missing-part), rejected (entry 2: missing-part); execution: analysed
  call to leaf: lookup: rejected (entry 1: missing-part), rejected (entry 2: missing-part); execution: analysed
  $ EVA_TEST_CACHE_PARTS=logic frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -calldeps -eva-slevel 20 logic_wider.c > logic_wider.log 2>&1
  $ grep -E '^(entry of|leaf|logic inputs)' logic_wider.log
  entry of leaf: parts [from]
  entry of leaf: parts [from]
  entry of leaf: parts [from]
  entry of leaf: parts [from]
  leaf: hits 0, rejected for missing-part 16
  leaf at line 16: logic inputs a; b; p; caching disabled a; b; p
  leaf at line 17: logic inputs a; p; caching disabled a; p
  logic inputs equal to caching disabled: true
  $ EVA_TEST_CACHE_PARTS=logic frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -calldeps logic_wider.c > logic_joined.log 2>&1
  $ grep -E '^(entry of|leaf|logic inputs)' logic_joined.log
  entry of leaf: parts [from]
  entry of leaf: parts [from]
  leaf: hits 0, rejected for missing-part 4
  leaf at line 16: logic inputs a; b; p; caching disabled a; b; p
  leaf at line 17: logic inputs a; p; caching disabled a; p
  logic inputs equal to caching disabled: true

From and Inout compute their results by function from the states that Eva
saves at the statements of each body. When one of these results is
requested, every candidate is rejected (consumer). The callwise results of
-inout need no such state: its calls hit.

  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -deps parts.c > deps.log 2>&1
  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -out parts.c > out.log 2>&1
  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -out-external parts.c > out-external.log 2>&1
  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -input parts.c > input.log 2>&1
  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -input-with-formals parts.c > input-with-formals.log 2>&1
  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -deref parts.c > deref.log 2>&1
  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -inout parts.c > inout-option.log 2>&1
  $ grep '^hits' deps.log out.log out-external.log input.log input-with-formals.log deref.log inout-option.log
  deps.log:hits 0, rejected for consumer 15
  out.log:hits 0, rejected for consumer 15
  out-external.log:hits 0, rejected for consumer 15
  input.log:hits 0, rejected for consumer 15
  input-with-formals.log:hits 0, rejected for consumer 15
  deref.log:hits 0, rejected for consumer 15
  inout-option.log:hits 7, rejected for consumer 0

The plug-ins that request these results by function reject every
candidate when they are loaded. The rule is by dependency: Pdg, Reduc and
Studia are named, and a plug-in that loads one of them is covered by it.
Impact, Scope, Security-slicing, Slicing and Sparecode all load Pdg, and
Dive loads Studia; Slicing and Dive are tested here. Occurrence reads the
states saved at the statements, and drops an access whose address is not
precise: loaded, it rejects every candidate too. So do the other plug-ins
that read these states and are not shown to conclude soundly from the top
state: Nonterm, Metrics, the constant propagation, WP and the Markdown
report.

  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,pdg,test_cache_parts.cmxs parts.c > pdg.log 2>&1
  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,reduc,test_cache_parts.cmxs parts.c > reduc.log 2>&1
  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,studia,test_cache_parts.cmxs parts.c > studia.log 2>&1
  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,slicing,test_cache_parts.cmxs parts.c > slicing.log 2>&1
  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,dive,test_cache_parts.cmxs parts.c > dive.log 2>&1
  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,occurrence,test_cache_parts.cmxs parts.c > occurrence.log 2>&1
  $ grep '^hits' pdg.log reduc.log studia.log slicing.log dive.log occurrence.log
  pdg.log:hits 0, rejected for consumer 15
  reduc.log:hits 0, rejected for consumer 15
  studia.log:hits 0, rejected for consumer 15
  slicing.log:hits 0, rejected for consumer 15
  dive.log:hits 0, rejected for consumer 15
  occurrence.log:hits 0, rejected for consumer 15
  $ for m in nonterm metrics constant_propagation wp markdown-report,markdown-report.eva-info; do EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,$m,test_cache_parts.cmxs parts.c > reader.log 2>&1; echo "$m: $(grep '^hits' reader.log)"; done
  nonterm: hits 0, rejected for consumer 15
  metrics: hits 0, rejected for consumer 15
  constant_propagation: hits 0, rejected for consumer 15
  wp: hits 0, rejected for consumer 15
  markdown-report,markdown-report.eva-info: hits 0, rejected for consumer 15

The name of a part is its key: registering a second part named as a
registered one is refused.

  $ EVA_TEST_CACHE_PARTS=duplicate frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > duplicate.log 2>&1
  $ grep -E '^(refused|registered)' duplicate.log
  refused: Cache_part.register: a part named from is already registered

A hit restores the parts through the functions that their owners register,
and these functions run clients. The lookup rejects every supplied entry,
with callback, while a part needed in the analysis is not registered as
audited. The test module registers a part, needed in both analyses, and
gives its value for every body: the entries carry it. Not audited, the part
leaves copy without a hit; audited, the three calls hit.

  $ EVA_TEST_CACHE_PARTS=unaudited-part frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > unaudited-part.log 2>&1
  $ EVA_TEST_CACHE_PARTS=unaudited-part EVA_TEST_CACHE_PARTS_AUDITED=1 frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > audited-part.log 2>&1
  $ grep '^copy' unaudited-part.log audited-part.log
  unaudited-part.log:copy: hits 0, rejected for callback 9
  audited-part.log:copy: hits 3, rejected for callback 0

The part of Inout runs the clients of its hook on the inputs and outputs of
each call. Eva registers its own client, which reduces the actuals of the
call, as audited; a client registered through register_call_hook, the
dynamic access of Inout, is not, and the lookup rejects every supplied
entry.

  $ EVA_TEST_CACHE_PARTS=inout-client frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > inout-client.log 2>&1
  $ grep '^copy' inout-client.log
  copy: hits 0, rejected for callback 9

The predicate of a part that tells whether its consumer is enabled is client
code. The lookup evaluates the predicates of all parts once, before its test
of the clients that are not audited, and the check of the parts and the
restoration use these decisions: no predicate runs between the test and the
end of the delivery. The test module registers a part, not audited and never
needed, whose predicate registers a call hook of Eva at its first, then at
its second evaluation in the second analysis. At its first, the hook is
registered by the first lookup of copy, whose test rejects the three
candidates with callback. At its second, the first call to copy hits and the
two others are rejected. The hook never receives a call with Reuse, and the
predicate runs once for each of the seven lookups with candidates.

  $ EVA_TEST_CACHE_PARTS=predicate frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > predicate.log 2>&1
  $ EVA_TEST_CACHE_PARTS=predicate EVA_TEST_CACHE_PARTS_ARM=2 frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > predicate-second.log 2>&1
  $ grep -E '^(copy|hook)' predicate.log predicate-second.log
  predicate.log:copy: hits 0, rejected for callback 9
  predicate.log:hook: 0 calls with Reuse; predicate evaluated 7 times
  predicate-second.log:copy: hits 1, rejected for callback 6
  predicate-second.log:hook: 0 calls with Reuse; predicate evaluated 7 times

The lookup evaluates every predicate needed of the parts and every
predicate of the readers of the statement states before it asks the parts
whose consumer is enabled whether they are audited: a client that one of
these predicates registers is seen by the audit of the same lookup. Below,
the predicate registers a client of the hook of Inout through its dynamic
access at its first evaluation, as the predicate of a part, then as that
of a reader. The audit of the part of Inout, asked afterwards, answers that
it is not audited: the three calls to copy reject their candidates with
callback, and the client receives no call after a hit on copy.

  $ EVA_TEST_CACHE_PARTS=predicate EVA_TEST_CACHE_PARTS_CLIENT=inout frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > predicate-inout.log 2>&1
  $ EVA_TEST_CACHE_PARTS=predicate EVA_TEST_CACHE_PARTS_CLIENT=inout EVA_TEST_CACHE_PARTS_CARRIER=reader frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > reader-inout.log 2>&1
  $ grep -E '^(copy|inout client)' predicate-inout.log reader-inout.log
  predicate-inout.log:copy: hits 0, rejected for callback 9
  predicate-inout.log:inout client: 0 calls after a hit on copy
  reader-inout.log:copy: hits 0, rejected for callback 9
  reader-inout.log:inout client: 0 calls after a hit on copy

A part registered since the lookup took the answers of the predicates has
no answer, and counts as a part that is not audited. Here the predicate
registers a part never needed at its first evaluation: the first lookup of
copy rejects its three candidates with callback; the next lookups take the
answers of the new part as well, and the two other calls to copy hit.

  $ EVA_TEST_CACHE_PARTS=predicate EVA_TEST_CACHE_PARTS_CLIENT=part frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > predicate-part.log 2>&1
  $ grep -E '^copy' predicate-part.log
  copy: hits 2, rejected for callback 3

A hit updates the statistics by function of the summary after its delivery,
as the end of an analysis of the body does, and the update runs the
subscribers of these statistics. A subscriber registered without an audit
makes the lookup reject every supplied entry with callback. The test module
registers one, which records at each update of the statistics of copy
whether the results at the statements are complete and how many statements
of copy are reached: three updates by the calls and one by the end of each
analysis. Registered as audited, it lets the three calls hit, and sees the
same updates as after the analysis with caching disabled, but with results
at the statements that are not complete: the statistics of a function
answered by hits count its statements as reached.

  $ EVA_TEST_CACHE_PARTS=stats frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > stats.log 2>&1
  $ EVA_TEST_CACHE_PARTS=stats EVA_TEST_CACHE_PARTS_AUDITED=1 frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > stats-audited.log 2>&1
  $ grep -E '^(copy|updates)' stats.log stats-audited.log
  stats.log:updates of copy, caching disabled: complete true, reached 2; complete true, reached 2; complete true, reached 2; complete true, reached 2
  stats.log:updates of copy, second analysis: complete true, reached 2; complete true, reached 2; complete true, reached 2; complete true, reached 2
  stats.log:copy: hits 0, rejected for callback 9
  stats-audited.log:updates of copy, caching disabled: complete true, reached 2; complete true, reached 2; complete true, reached 2; complete true, reached 2
  stats-audited.log:updates of copy, second analysis: complete false, reached 2; complete false, reached 2; complete false, reached 2; complete false, reached 2
  stats-audited.log:copy: hits 3, rejected for callback 0

The summary installs, once and when Eva is loaded, what a hit runs after
its delivery. A second installation, through the internal modules of Eva,
is refused, and the hits run what the summary installed.

  $ EVA_TEST_CACHE_PARTS=replace-summary frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > replace-summary.log 2>&1
  $ grep -E '^(refused|installed|replaced|copy)' replace-summary.log
  refused: Safety_delivery.on_delivered: the summary of the analysis is already installed
  copy: hits 3

The hook of Inout leaves the inputs and outputs of each call in a cell,
which the caller reads to reduce its actuals; the call statement empties it
afterwards. The entry point has no caller: its call empties the cell too,
whether its body is analysed or a hit answers it. In root.c, main makes no
call: its entry, produced with caching disabled, answers it in the second
analysis.

  $ EVA_TEST_CACHE_PARTS=root frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs root.c > root.log 2>&1
  $ grep -E '^(caching disabled|second analysis)' root.log
  caching disabled: entries of main 1, Inout cell empty
  second analysis: hits of main 1, Inout cell empty

After an analysis in which hits answered calls, the results by function of
From and Inout, and the results by statement of Inout, are computed from
states that do not cover these calls. Every request is refused with a user
error, whoever makes it: the module supplying the entries, through the API
of From and Inout or through the dynamic access to Inout that Eva also
uses. A later analysis with caching disabled computes them again, equal to
those of the first analysis.

  $ EVA_TEST_CACHE_PARTS=api frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > api.log 2>&1
  $ grep -E '^(hits|From|Inout|after an analysis)|User Error' api.log
  hits: copy 3; statement results complete: false
  [from] User Error: cannot compute the dependencies by function: in the current analysis of Eva, a hit of the cache answered a call without analysing the body of the called function, and saved no state at its statements
  From.get: refused
  [inout] User Error: cannot compute the inputs and outputs by function or by statement: in the current analysis of Eva, a hit of the cache answered a call without analysing the body of the called function, and saved no state at its statements
  Inout.kf_inputs: refused
  [inout] User Error: cannot compute the inputs and outputs by function or by statement: in the current analysis of Eva, a hit of the cache answered a call without analysing the body of the called function, and saved no state at its statements
  Inout.stmt_inputs: refused
  [inout] User Error: cannot compute the inputs and outputs by function or by statement: in the current analysis of Eva, a hit of the cache answered a call without analysing the body of the called function, and saved no state at its statements
  Inout.stmt_outputs: refused
  [inout] User Error: cannot compute the inputs and outputs by function or by statement: in the current analysis of Eva, a hit of the cache answered a call without analysing the body of the called function, and saved no state at its statements
  Inout.expr_inputs: refused
  [inout] User Error: cannot compute the inputs and outputs by function or by statement: in the current analysis of Eva, a hit of the cache answered a call without analysing the body of the called function, and saved no state at its statements
  Inout.kf_outputs, by the dynamic access: refused
  after an analysis with caching disabled: statement results complete: true; results by function equal: true

The options that print these results, set by -then after the analysis with
hits, stop with the same error, without printing a result.

  $ EVA_TEST_CACHE_PARTS=then frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c -then -deps -input > then.log 2>&1
  [1]
  $ grep -E '^hits|User Error|Function|Inputs' then.log
  hits: copy 3; statement results complete: false
  [from] User Error: cannot compute the dependencies by function: in the current analysis of Eva, a hit of the cache answered a call without analysing the body of the called function, and saved no state at its statements
  $ EVA_TEST_CACHE_PARTS=then frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c -then -input > then-input.log 2>&1
  [1]
  $ grep -E '^hits|User Error|Function|Inputs' then-input.log
  hits: copy 3; statement results complete: false
  [inout] User Error: cannot compute the inputs and outputs by function or by statement: in the current analysis of Eva, a hit of the cache answered a call without analysing the body of the called function, and saved no state at its statements
  $ EVA_TEST_CACHE_PARTS=then frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c -then -out-external > then-out-external.log 2>&1
  [1]
  $ EVA_TEST_CACHE_PARTS=then frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c -then -input-with-formals > then-input-with-formals.log 2>&1
  [1]
  $ EVA_TEST_CACHE_PARTS=then frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c -then -deref > then-deref.log 2>&1
  [1]
  $ grep -c 'User Error: cannot compute the inputs and outputs' then-out-external.log then-input-with-formals.log then-deref.log
  then-out-external.log:1
  then-input-with-formals.log:1
  then-deref.log:1

From.get starts the analysis when its results are not computed. The first
request after the entries are supplied starts the analysis in which the
three calls to copy hit: it is refused, as the second one.

  $ EVA_TEST_CACHE_PARTS=lazy-from frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > lazy-from.log 2>&1
  $ grep -E '^(first|second|hits|after)|User Error' lazy-from.log
  [from] User Error: cannot compute the dependencies by function: in the current analysis of Eva, a hit of the cache answered a call without analysing the body of the called function, and saved no state at its statements
  first request: refused
  hits: copy 3; statement results complete: false
  [from] User Error: cannot compute the dependencies by function: in the current analysis of Eva, a hit of the cache answered a call without analysing the body of the called function, and saved no state at its statements
  second request: refused
  after an analysis with caching disabled: equal to the first analysis: true

Results requested at the start of the analysis with the supplied entries,
before any hit, are computed and memoised from the states then available,
as with caching disabled. After the hits, each request is refused, those
memoised included.

  $ EVA_TEST_CACHE_PARTS=warm frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > warm.log 2>&1
  $ grep -E '^(at the start|after the hits|hits|after an analysis)|User Error' warm.log
  at the start: Inout.kf_external_inputs: computed
  at the start: Inout.kf_external_outputs: computed
  at the start: Inout.kf_inputs: computed
  at the start: Inout.kf_outputs: computed
  hits: copy 3; statement results complete: false
  [inout] User Error: cannot compute the inputs and outputs by function or by statement: in the current analysis of Eva, a hit of the cache answered a call without analysing the body of the called function, and saved no state at its statements
  after the hits: Inout.kf_external_inputs: refused
  [inout] User Error: cannot compute the inputs and outputs by function or by statement: in the current analysis of Eva, a hit of the cache answered a call without analysing the body of the called function, and saved no state at its statements
  after the hits: Inout.kf_external_outputs: refused
  [inout] User Error: cannot compute the inputs and outputs by function or by statement: in the current analysis of Eva, a hit of the cache answered a call without analysing the body of the called function, and saved no state at its statements
  after the hits: Inout.kf_inputs: refused
  [inout] User Error: cannot compute the inputs and outputs by function or by statement: in the current analysis of Eva, a hit of the cache answered a call without analysing the body of the called function, and saved no state at its statements
  after the hits: Inout.kf_outputs: refused
  after an analysis with caching disabled: equal to the first analysis: true

The inputs and outputs of unused in nested.c, which no call reaches,
requested at the start of the analysis with the supplied entries. Inout
starts an analysis of the program, here with -deps set, which rejects every
candidate: its results are complete, and the result of unused is computed
from the states saved at its statements and memoised. -deps is unset, and
the analysis takes hits. After the hits, the result of unused is refused,
and that of inner, joined from the results of its calls, is not.

  $ EVA_TEST_CACHE_PARTS=fallback frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs nested.c > fallback.log 2>&1
  $ grep -E '^(at the start|inner|after the hits)' fallback.log
  at the start, with -deps: Inout.get_precise_inout of unused: computed
  inner: hits 2; statement results complete: false
  after the hits: Inout.get_precise_inout of unused: refused
  after the hits: Inout.get_precise_inout of inner equal to caching disabled: true

The same on the three requests of Inout on the external view of a function,
each of which tests the refusal before its own table: the dereferenced zones
and the operational inputs, without the formals and with them. Their tables
are filled at the start, with -deps; after the hits, each request is
refused.

  $ EVA_TEST_CACHE_PARTS=external frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs nested.c > external.log 2>&1
  $ grep -E '^(at the start|inner|after the hits)' external.log
  at the start, with -deps: the dereferenced zones of inner: computed
  at the start, with -deps: the operational inputs of unused: computed
  at the start, with -deps: the operational inputs of unused with its formals: computed
  inner: hits 2; statement results complete: false
  after the hits: the dereferenced zones of inner: refused
  after the hits: the operational inputs of unused: refused
  after the hits: the operational inputs of unused with its formals: refused

The results of an analysis taken and installed again keep the record of the
hits: installed in turn, the results with hits refuse the dependencies by
function, and those of caching disabled give them.

  $ EVA_TEST_CACHE_PARTS=snapshot frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > snapshot.log 2>&1
  $ grep -E '^(installed|From.get)' snapshot.log
  installed the results with hits: statement results complete: false
  From.get: refused
  installed the results of caching disabled: statement results complete: true
  From.get: equal to the first analysis: true
  installed the results with hits: statement results complete: false
  From.get: refused

A change of an option of Eva while the analysis runs clears its results.
The test module adds copy to -eva-no-results-function at the first call to
copy, which hits: the entries were produced while the results of copy were
saved, and the later calls to copy are not answered by them.

  $ EVA_TEST_CACHE_PARTS=reset frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -eva-msg-key cache parts.c > reset.log 2>&1
  $ grep -E '^copy after' reset.log
  copy after the change: hits 0, rejected for analysis-reset 6
  $ grep -o 'call to copy: lookup: [^;]*; execution: [a-z-]*' reset.log | tail -3
  call to copy: lookup: hit (entry 1); execution: not-analysed
  call to copy: lookup: rejected (entry 1: analysis-reset), rejected (entry 2: analysis-reset), rejected (entry 3: analysis-reset); execution: analysed
  call to copy: lookup: rejected (entry 1: analysis-reset), rejected (entry 2: analysis-reset), rejected (entry 3: analysis-reset); execution: analysed

A copy of the project made after the hits carries the record of the hits:
in the copy, the dependencies by function are refused.

  $ EVA_TEST_CACHE_PARTS=copy frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > copy.log 2>&1
  $ grep -E '^(hits|in the copy)' copy.log
  hits: copy 3; statement results complete: false
  in the copy: statement results complete: false
  in the copy: From.get: refused

The record of the hits is saved with the session: another process that
loads it refuses the same requests.

  $ EVA_TEST_CACHE_PARTS=save EVA_TEST_CACHE_PARTS_SESSION=hits.sav frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > save.log 2>&1
  $ grep -E '^hits' save.log
  hits: copy 3; statement results complete: false
  $ frama-c -no-autoload-plugins -load-module eva,from,inout -load hits.sav -deps > load-deps.log 2>&1
  [1]
  $ grep -E 'User Error|Function' load-deps.log
  [from] User Error: cannot compute the dependencies by function: in the current analysis of Eva, a hit of the cache answered a call without analysing the body of the called function, and saved no state at its statements
  $ frama-c -no-autoload-plugins -load-module eva,from,inout -load hits.sav -out > load-out.log 2>&1
  [1]
  $ grep -E 'User Error|Function|Out' load-out.log
  [inout] User Error: cannot compute the inputs and outputs by function or by statement: in the current analysis of Eva, a hit of the cache answered a call without analysing the body of the called function, and saved no state at its statements

A plug-in that reads the states saved at the statements and is loaded
after the hits was not seen by the lookups. While one is loaded, the
results of Eva refuse to give a state at a statement after a hit. Each of
the plug-ins below, loaded in the process that loads the session, stops
with this error at its first request of a state: Occurrence, Nonterm,
Metrics, after its count of the functions called, the constant propagation,
WP with its memory model based on Eva, the Markdown report, Slicing, which
reads the results of Eva beside the graphs of Pdg, and Dive, which loads
Studia. The error names the first plug-in of the list that is loaded.

  $ frama-c -no-autoload-plugins -load-module eva,from,inout,occurrence -load hits.sav -occurrence > late-occurrence.log 2>&1
  [1]
  $ frama-c -no-autoload-plugins -load-module eva,from,inout,nonterm -load hits.sav -nonterm > late-nonterm.log 2>&1
  [1]
  $ frama-c -no-autoload-plugins -load-module eva,from,inout,metrics -load hits.sav -metrics-eva-cover > late-metrics.log 2>&1
  [1]
  $ frama-c -no-autoload-plugins -load-module eva,from,inout,constant_propagation -load hits.sav -scf > late-scf.log 2>&1
  [1]
  $ frama-c -no-autoload-plugins -load-module eva,from,inout,wp -load hits.sav -wp -wp-model eva > late-wp.log 2>&1
  [1]
  $ frama-c -no-autoload-plugins -load-module eva,from,inout,markdown-report,markdown-report.eva-info -load hits.sav -mdr-gen md -mdr-out late.md > late-mdr.log 2>&1
  [1]
  $ frama-c -no-autoload-plugins -load-module eva,from,inout,slicing -load hits.sav -slice-return main > late-slicing.log 2>&1
  [1]
  $ frama-c -no-autoload-plugins -load-module eva,from,inout,dive -load hits.sav -dive-from-variables narrow::x -dive-output-dot late.dot > late-dive.log 2>&1
  [1]
  $ grep -o 'User Error.*' late-occurrence.log late-nonterm.log late-metrics.log late-scf.log late-wp.log late-mdr.log late-slicing.log late-dive.log | sed 's/: in the current analysis.*statements//'
  late-occurrence.log:User Error: cannot give the state at a statement; plug-in occurrence, which reads these states, is loaded
  late-nonterm.log:User Error: cannot give the state at a statement; plug-in nonterm, which reads these states, is loaded
  late-metrics.log:User Error: cannot give the state at a statement; plug-in metrics, which reads these states, is loaded
  late-scf.log:User Error: cannot give the state at a statement; plug-in scf, which reads these states, is loaded
  late-wp.log:User Error: cannot give the state at a statement; plug-in wp, which reads these states, is loaded
  late-mdr.log:User Error: cannot give the state at a statement; plug-in mdr, which reads these states, is loaded
  late-slicing.log:User Error: cannot give the state at a statement; plug-in pdg, which reads these states, is loaded
  late-dive.log:User Error: cannot give the state at a statement; plug-in studia, which reads these states, is loaded
  $ tail -q -n 1 late-occurrence.log late-nonterm.log late-metrics.log late-scf.log late-wp.log late-mdr.log late-slicing.log late-dive.log | sort | uniq -c
        8 [kernel] Plug-in eva aborted: invalid user input.

The other plug-ins that load Pdg. Sparecode asks the graph of a function
first, and stops with the refusal of Pdg. Scope, Impact and Security
slicing have no option that runs them on a program without annotations of
their own: a test module asks one result of each through its interface,
about b before the last call to copy in deps_main, on a session saved after
an analysis with caching disabled, then on the session with hits. The
requests of Scope read the results of Eva at statements and are refused by
Eva; those of Impact and of Security slicing ask a graph and are refused by
Pdg.

  $ frama-c -no-autoload-plugins -load-module eva,from,inout,sparecode -load hits.sav -sparecode > late-sparecode.log 2>&1
  [1]
  $ grep -o 'User Error.*' late-sparecode.log | sed 's/: in the current analysis.*statements//'
  User Error: cannot compute the dependence graph of a function
  $ frama-c -no-autoload-plugins -load-module eva,from,inout -eva -eva-no-memexec -save fresh.sav parts.c > save-fresh.log 2>&1
  $ frama-c -no-autoload-plugins -load-module eva,from,inout,scope,impact,security_slicing,test_cache_parts_readers.cmxs -load fresh.sav > api-fresh.log 2>&1
  $ grep -E 'complete|computed|refused' api-fresh.log
  statement results complete: true
  Scope.Datascope.get_data_scope_at_stmt: computed
  Scope.Defs.get_defs: computed
  Scope.Zones.build_zones: computed
  Impact.Register.from_stmt: computed
  Security_slicing.Components.get_direct_component: computed
  $ frama-c -no-autoload-plugins -load-module eva,from,inout,scope,impact,security_slicing,test_cache_parts_readers.cmxs -load hits.sav > api-hits.log 2>&1
  $ grep -E 'complete|computed|refused' api-hits.log
  statement results complete: false
  Scope.Datascope.get_data_scope_at_stmt: refused by eva
  Scope.Defs.get_defs: refused by eva
  Scope.Zones.build_zones: refused by eva
  Impact.Register.from_stmt: refused by pdg
  Security_slicing.Components.get_direct_component: refused by pdg

Reduc starts from the alarms, and parts.c has none. alarm.c calls the main
function of parts.c, then divides by a volatile value. On the session saved
after the analysis of alarm.c with hits, Reduc asks Inout the outputs of the
statement of the alarm, and stops with the refusal of Inout; on an analysis
with caching disabled, it runs to its end.

  $ EVA_TEST_CACHE_PARTS=save EVA_TEST_CACHE_PARTS_SESSION=alarm.sav frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs alarm.c > save-alarm.log 2>&1
  $ grep -E '^hits|division by zero. assert' save-alarm.log | sort -u
  [eva:alarm] alarm.c:12: Warning: division by zero. assert any ≢ 0;
  hits: copy 3; statement results complete: false
  $ frama-c -no-autoload-plugins -load-module eva,from,inout,reduc -load alarm.sav -reduc > late-reduc.log 2>&1
  [1]
  $ grep -o 'User Error.*' late-reduc.log | sed 's/: in the current analysis.*statements//'
  User Error: cannot compute the inputs and outputs by function or by statement
  $ frama-c -no-autoload-plugins -load-module eva,from,inout,reduc -eva -eva-no-memexec -reduc alarm.c > fresh-reduc.log 2>&1
  $ grep -c 'User Error' fresh-reduc.log
  0
  [1]

The display of the callwise dependencies of From asks the results of Eva
the function called at each call site, in the analysed callers. A session
is saved with -calldeps after the analysis with hits. Loaded with no reader
of the statement states, From displays the dependencies of an analysis with
caching disabled. Loaded with Occurrence, the display stops with the
refusal of Eva, before Occurrence asks anything: the refusal is for every
reader of the process.

  $ EVA_TEST_CACHE_PARTS=save EVA_TEST_CACHE_PARTS_SESSION=calldeps.sav frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -calldeps parts.c > save-calldeps.log 2>&1
  $ grep '^hits' save-calldeps.log
  hits: copy 3; statement results complete: false
  $ frama-c -no-autoload-plugins -load-module eva,from,inout -load calldeps.sav > load-calldeps.log 2>&1
  $ frama-c -no-autoload-plugins -load-module eva,from,inout -calldeps -eva-no-memexec parts.c > calldeps-disabled.log 2>&1
  $ sed -n '/DISPLAYING CALLWISE/,/END OF/p' load-calldeps.log > calldeps-loaded.txt
  $ sed -n '/DISPLAYING CALLWISE/,/END OF/p' calldeps-disabled.log > calldeps-disabled.txt
  $ cmp calldeps-loaded.txt calldeps-disabled.txt
  $ grep -c 'call to' calldeps-loaded.txt
  9
  $ frama-c -no-autoload-plugins -load-module eva,from,inout,occurrence -load calldeps.sav > load-calldeps-reader.log 2>&1
  [1]
  $ grep -E 'DISPLAYING|call to|User Error|beginning analysis' load-calldeps-reader.log | sed 's/: in the current analysis.*statements//'
  [from] ====== DISPLAYING CALLWISE DEPENDENCIES ======
  [eva] User Error: cannot give the state at a statement; plug-in occurrence, which reads these states, is loaded

The same in one process, in the scenario late-reader: the requests of the
results at the first statement of copy and at its start are answered after
the hits, with the state top. Once Occurrence is loaded, they are refused,
in the project, in a copy of it, and when the results with hits are
installed again by Eva_results.set_results; the results of the analysis
with caching disabled, installed in between, are given. The initial state
is always given.

  $ EVA_TEST_CACHE_PARTS=late-reader frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > late-reader.log 2>&1
  $ sed -n '/^hits/,$p' late-reader.log > late-reader.txt
  $ grep -vE 'User Error|^ ' late-reader.txt
  hits: copy 3; statement results complete: false
  after the hits: state before a statement: computed
  after the hits: state after a statement: computed
  after the hits: state at the start of a function: computed
  after the hits: states by callstack: computed
  after the hits: callstacks of a statement: computed
  after the hits: callstacks of a statement, from the engine: computed
  after the hits: reachability of a statement: computed
  after the hits: initial state: computed
  with a reader loaded: state before a statement: refused
  with a reader loaded: state after a statement: refused
  with a reader loaded: state at the start of a function: refused
  with a reader loaded: states by callstack: refused
  with a reader loaded: callstacks of a statement: refused
  with a reader loaded: callstacks of a statement, from the engine: refused
  with a reader loaded: reachability of a statement: refused
  with a reader loaded: initial state: computed
  in a copy: state before a statement: refused
  in a copy: state after a statement: refused
  in a copy: state at the start of a function: refused
  in a copy: states by callstack: refused
  in a copy: callstacks of a statement: refused
  in a copy: callstacks of a statement, from the engine: refused
  in a copy: reachability of a statement: refused
  in a copy: initial state: computed
  results of caching disabled installed: state before a statement: computed
  results of caching disabled installed: state after a statement: computed
  results of caching disabled installed: state at the start of a function: computed
  results of caching disabled installed: states by callstack: computed
  results of caching disabled installed: callstacks of a statement: computed
  results of caching disabled installed: callstacks of a statement, from the engine: computed
  results of caching disabled installed: reachability of a statement: computed
  results of caching disabled installed: initial state: computed
  results with hits installed: state before a statement: refused
  results with hits installed: state after a statement: refused
  results with hits installed: state at the start of a function: refused
  results with hits installed: states by callstack: refused
  results with hits installed: callstacks of a statement: refused
  results with hits installed: callstacks of a statement, from the engine: refused
  results with hits installed: reachability of a statement: refused
  results with hits installed: initial state: computed
  in a copy of the installed results: state before a statement: refused
  in a copy of the installed results: state after a statement: refused
  in a copy of the installed results: state at the start of a function: refused
  in a copy of the installed results: states by callstack: refused
  in a copy of the installed results: callstacks of a statement: refused
  in a copy of the installed results: callstacks of a statement, from the engine: refused
  in a copy of the installed results: reachability of a statement: refused
  in a copy of the installed results: initial state: computed

The same scenario under the options that decide which states are saved, set
in the producing analysis, in the using one or in both, as for the final
values above. Each line counts the requests refused among the seven at a
statement or at the start of a function, at each moment of the scenario.
The refusal does not depend on the option: where a call hit, the seven are
refused once the reader is loaded, in a copy and with the results with hits
installed, and none is refused before the reader is loaded or with the
results of caching disabled installed. With -eva-no-results in the
producing analysis alone, every candidate is rejected (missing-points), no
call hits, and nothing is refused. With -eva-no-results-function copy in
the producing analysis alone, copy does not hit and the other callees do.

  $ refused() { grep -c "^$1: .*: refused\$" late-option.log; }
  $ for o in results function domain; do for w in producer consumer both; do EVA_TEST_CACHE_PARTS=late-reader EVA_TEST_CACHE_PARTS_OPTION=$o EVA_TEST_CACHE_PARTS_WHERE=$w frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > late-option.log 2>&1; echo "$o, $w: $(grep '^hits' late-option.log); refused: after the hits $(refused 'after the hits'), with a reader loaded $(refused 'with a reader loaded'), in a copy $(refused 'in a copy'), caching disabled installed $(refused 'results of caching disabled installed'), hits installed $(refused 'results with hits installed'), copy of the installed $(refused 'in a copy of the installed results')"; done; done
  results, producer: hits: copy 0; statement results complete: true; refused: after the hits 0, with a reader loaded 0, in a copy 0, caching disabled installed 0, hits installed 0, copy of the installed 0
  results, consumer: hits: copy 3; statement results complete: false; refused: after the hits 0, with a reader loaded 7, in a copy 7, caching disabled installed 0, hits installed 7, copy of the installed 7
  results, both: hits: copy 3; statement results complete: false; refused: after the hits 0, with a reader loaded 7, in a copy 7, caching disabled installed 0, hits installed 7, copy of the installed 7
  function, producer: hits: copy 0; statement results complete: false; refused: after the hits 0, with a reader loaded 7, in a copy 7, caching disabled installed 0, hits installed 7, copy of the installed 7
  function, consumer: hits: copy 3; statement results complete: false; refused: after the hits 0, with a reader loaded 7, in a copy 7, caching disabled installed 0, hits installed 7, copy of the installed 7
  function, both: hits: copy 3; statement results complete: false; refused: after the hits 0, with a reader loaded 7, in a copy 7, caching disabled installed 0, hits installed 7, copy of the installed 7
  domain, producer: hits: copy 3; statement results complete: false; refused: after the hits 0, with a reader loaded 7, in a copy 7, caching disabled installed 0, hits installed 7, copy of the installed 7
  domain, consumer: hits: copy 3; statement results complete: false; refused: after the hits 0, with a reader loaded 7, in a copy 7, caching disabled installed 0, hits installed 7, copy of the installed 7
  domain, both: hits: copy 3; statement results complete: false; refused: after the hits 0, with a reader loaded 7, in a copy 7, caching disabled installed 0, hits installed 7, copy of the installed 7

Requests of the server: the dead code of copy and of narrow, whose two
branches are reached, and the values of *src in copy, as the graphical
interface asks them, asked before and after Studia is loaded, and the
statements that read and that write b, which Studia, loaded after the
analysis, computes with Inout. The server, which From and Inout load through
Callgraph, registers a client of the hooks on the changes of annotations;
the client emits a signal to the client of the server, and the lookup
admits the entries while it is registered. After an analysis with caching
disabled, the server answers every request. After the analysis with hits,
in the same process and in the session saved above, the requests of Eva
made before Studia is loaded give the statements of caching disabled, since
the hits deliver the points that they reach, and the values of *src in copy
are those of the state top, where caching disabled gives 1 or 2. Once
Studia is loaded, the results of Eva refuse the states at the statements:
the dead code of copy and the values are refused, and so is the request of
the reads of an lvalue, which locates it with these results. The requests of the reads and of the writes of b
named by its declaration need no state for the location, and Studia refuses
each by its own test.

  $ EVA_TEST_CACHE_PARTS_SERVER=fresh frama-c -no-autoload-plugins -load-module eva,eva.server_api,from,inout,test_cache_parts_server.cmxs parts.c > server-fresh.log 2>&1
  $ grep -E '^(statement|plugins|copy:|narrow:|declaration:|Studia)' server-fresh.log
  statement results complete: true
  copy: plugins.eva.ast.getDeadCode: unreachable 0, reached 2, nonTerminating 0
  narrow: plugins.eva.ast.getDeadCode: unreachable 0, reached 4, nonTerminating 0
  plugins.eva.values.getValues: *src in copy: {1; 2}
  Studia loaded
  copy: plugins.eva.ast.getDeadCode: unreachable 0, reached 2, nonTerminating 0
  plugins.eva.values.getValues: *src in copy: {1; 2}
  plugins.studia.studia.getReadsLval: indirect 4, direct 1
  declaration: plugins.studia.studia.getReadsLval: indirect 4, direct 1
  plugins.studia.studia.getWritesLval: indirect 0, direct 1
  $ EVA_TEST_CACHE_PARTS_SERVER=hits frama-c -no-autoload-plugins -load-module eva,eva.server_api,from,inout,test_cache_parts_server.cmxs parts.c > server-hits.log 2>&1
  $ sed -n '/^hits/,$p' server-hits.log > server-hits.txt
  $ grep -E '^(hits|statement|plugins|copy:|narrow:|declaration:|Studia)|User Error|Error when' server-hits.txt | sed 's/: in the current analysis.*statements//'
  hits: copy 3, narrow 1
  statement results complete: false
  copy: plugins.eva.ast.getDeadCode: unreachable 0, reached 2, nonTerminating 0
  narrow: plugins.eva.ast.getDeadCode: unreachable 0, reached 4, nonTerminating 0
  plugins.eva.values.getValues: *src in copy: {{ ANYTHING }} or UNINITIALIZED or ESCAPINGADDR
  Studia loaded
  [eva] User Error: cannot give the state at a statement; plug-in studia, which reads these states, is loaded
  copy: plugins.eva.ast.getDeadCode: refused
  [eva] User Error: cannot give the state at a statement; plug-in studia, which reads these states, is loaded
  plugins.eva.values.getValues: refused
  [eva] User Error: cannot give the state at a statement; plug-in studia, which reads these states, is loaded
  plugins.studia.studia.getReadsLval: refused
  [studia] User Error: cannot find the statements that access a location
  declaration: plugins.studia.studia.getReadsLval: refused
  [studia] User Error: cannot find the statements that access a location
  plugins.studia.studia.getWritesLval: refused
  $ EVA_TEST_CACHE_PARTS_SERVER=loaded frama-c -no-autoload-plugins -load-module eva,eva.server_api,from,inout,test_cache_parts_server.cmxs -load hits.sav > server.log 2>&1
  $ grep -E '^(statement|plugins|copy:|narrow:|declaration:|Studia)|User Error|Error when' server.log | sed 's/: in the current analysis.*statements//'
  statement results complete: false
  copy: plugins.eva.ast.getDeadCode: unreachable 0, reached 2, nonTerminating 0
  narrow: plugins.eva.ast.getDeadCode: unreachable 0, reached 4, nonTerminating 0
  plugins.eva.values.getValues: *src in copy: {{ ANYTHING }} or UNINITIALIZED or ESCAPINGADDR
  Studia loaded
  [eva] User Error: cannot give the state at a statement; plug-in studia, which reads these states, is loaded
  copy: plugins.eva.ast.getDeadCode: refused
  [eva] User Error: cannot give the state at a statement; plug-in studia, which reads these states, is loaded
  plugins.eva.values.getValues: refused
  [eva] User Error: cannot give the state at a statement; plug-in studia, which reads these states, is loaded
  plugins.studia.studia.getReadsLval: refused
  [studia] User Error: cannot find the statements that access a location
  declaration: plugins.studia.studia.getReadsLval: refused
  [studia] User Error: cannot find the statements that access a location
  plugins.studia.studia.getWritesLval: refused

Pdg, loaded in the process that loads the session, refuses to build the
graph of a function, and stops. With an option of Eva changed, the analysis
runs again, with caching disabled: the graph of copy is the one that an
analysis of the program with the same options builds, with the inputs b and
d.

  $ frama-c -no-autoload-plugins -load-module eva,from,inout,pdg -load hits.sav -fct-pdg copy > load-pdg.log 2>&1
  [1]
  $ grep -E 'User Error|Warning|PDG' load-pdg.log
  [pdg] User Error: cannot compute the dependence graph of a function: in the current analysis of Eva, a hit of the cache answered a call without analysing the body of the called function, and saved no state at its statements
  $ frama-c -no-autoload-plugins -load-module eva,from,inout,pdg -load hits.sav -eva-no-memexec -eva-slevel 1 -fct-pdg copy > load-pdg-again.log 2>&1
  $ frama-c -no-autoload-plugins -load-module eva,from,inout,pdg -eva-no-memexec -eva-slevel 1 -fct-pdg copy parts.c > pdg-disabled.log 2>&1
  $ sed -n '/PDG for copy/,$p' load-pdg-again.log > pdg-again.txt
  $ sed -n '/PDG for copy/,$p' pdg-disabled.log > pdg-disabled.txt
  $ cmp pdg-again.txt pdg-disabled.txt
  $ grep -E 'In\(' pdg-again.txt
   {n8}: In(b)
   {n9}: In(d)

The results of Eva at the statements of a function answered by hits, read
directly: the hits deliver the points that they reach, and the first
statement of copy is reachable, as with caching disabled. The state there is
top for the callstacks of the hits, and over all callstacks: src is
ANYTHING after the hits, where caching disabled gives &b or &d. The readers
above, which compute from these values, refuse them.

  $ EVA_TEST_CACHE_PARTS=raw frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > raw.log 2>&1
  $ grep -E 'reachable' raw.log
  caching disabled: first statement of copy reachable: true; src: {{ &b ; &d }}
  after the hits: first statement of copy reachable: true; src: {{ ANYTHING }}

A value of a part is kept with the entry only when it is given for the body
being analysed. The test module registers parts and gives a value of each
during the analysis of copy: for its callstack, and for the callstack of its
caller.

  $ EVA_TEST_CACHE_PARTS=project frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > project.log 2>&1
  $ grep '^entry of' project.log
  entry of copy: parts [inout, kept]
  entry of copy: parts [inout, kept]
  entry of copy: parts [inout, kept]
  entry of narrow: parts [inout]
  entry of narrow_and_write: parts [inout]
  entry of checked: parts [inout]
  entry of checked: parts [inout]

A value given while another project is current is computed in the tables of
that project. The test module also gives a value for the callstack of copy
while another project is current: the change of the current project during
the analysis of the body refuses it (project-switch), and no entry of copy
is produced.

  $ EVA_TEST_CACHE_PARTS=project EVA_TEST_CACHE_PARTS_SWITCH=1 frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -eva-msg-key cache parts.c > switch.log 2>&1
  $ grep -E '^entry of copy|call to copy' switch.log
    call to copy: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: refused (project-switch)
    call to copy: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: refused (project-switch)
    call to copy: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: refused (project-switch)

Entries are supplied to the project in which they were produced. A copy of
this project, made by Project.create_by_copy, has other values for its
functions, and the supply refuses the entries.

  $ EVA_TEST_CACHE_PARTS=copied frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > copied.log 2>&1
  $ grep -E 'supplied|refused|internal error' copied.log
  refused: Supplied_entries: the function copy of the entry is not a function of the current project; entries are supplied to the project whose AST they were made on
