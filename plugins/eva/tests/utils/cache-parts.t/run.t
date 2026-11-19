Parts of cache entries owned by From and Inout. In each scenario, a first
analysis with caching disabled produces the entries of the callees of
parts.c, which are then supplied to a second analysis. The test module
prints the parts of each entry and compares the two analyses.

  $ dune build -j 8 --cache=disabled --root . test_cache_parts.cmxs test_cache_parts_server.cmxs

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
values as with caching disabled. A function answered by hits only has no
state saved, and its final state is not printed.

  $ EVA_TEST_CACHE_PARTS=inout frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -eva parts.c > display.log 2>&1
  $ grep -o 'Values at end of function [a-z_]*' display.log | sort | uniq -c
        2 Values at end of function checked
        2 Values at end of function copy
        3 Values at end of function deps_main
        3 Values at end of function inout_main
        3 Values at end of function main
        2 Values at end of function narrow
        2 Values at end of function narrow_and_write
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
analysis. Their statuses are then removed. Both calls to checked hit in the
second analysis, and the hits check the clauses again.

  $ EVA_TEST_CACHE_PARTS=verify frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -from-verify-assigns parts.c > verify.log 2>&1
  $ grep -E '^(caching disabled|statuses removed|hits|after the hits)' verify.log
  caching disabled: assigns clause in function checked: VALID according to Eva
  caching disabled: from clause of term vout in function checked: VALID according to Eva
  statuses removed: assigns clause in function checked: no verification attempted
  statuses removed: from clause of term vout in function checked: no verification attempted
  hits: checked 2
  after the hits: assigns clause in function checked: VALID according to Eva
  after the hits: from clause of term vout in function checked: VALID according to Eva

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
Impact, Scope, Security-slicing, Slicing and Sparecode all load Pdg;
Slicing is tested here.

  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,pdg,test_cache_parts.cmxs parts.c > pdg.log 2>&1
  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,reduc,test_cache_parts.cmxs parts.c > reduc.log 2>&1
  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,studia,test_cache_parts.cmxs parts.c > studia.log 2>&1
  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,slicing,test_cache_parts.cmxs parts.c > slicing.log 2>&1
  $ grep '^hits' pdg.log reduc.log studia.log slicing.log
  pdg.log:hits 0, rejected for consumer 15
  reduc.log:hits 0, rejected for consumer 15
  studia.log:hits 0, rejected for consumer 15
  slicing.log:hits 0, rejected for consumer 15

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

Three requests of the server: the dead code of copy, and the statements
that read and that write b at the first call to copy, which Studia, loaded
after the analysis, computes with Inout. The server, which From and Inout
load through Callgraph, registers a client of the hooks on the changes of
annotations; the client emits a signal to the client of the server, and
the lookup admits the entries while it is registered. After an analysis
with caching disabled, the server answers the three requests. After the
analysis with hits, in the same process and in the session saved above,
the three requests are refused: the request of Eva answers with an error
of the server that names the cause.

  $ EVA_TEST_CACHE_PARTS_SERVER=fresh frama-c -no-autoload-plugins -load-module eva,eva.server_api,from,inout,test_cache_parts_server.cmxs parts.c > server-fresh.log 2>&1
  $ grep -E '^(statement|plugins)' server-fresh.log
  statement results complete: true
  plugins.eva.ast.getDeadCode: unreachable 0, reached 2, nonTerminating 0
  plugins.studia.studia.getReadsLval: indirect 4, direct 1
  plugins.studia.studia.getWritesLval: indirect 0, direct 1
  $ EVA_TEST_CACHE_PARTS_SERVER=hits frama-c -no-autoload-plugins -load-module eva,eva.server_api,from,inout,test_cache_parts_server.cmxs parts.c > server-hits.log 2>&1
  $ sed -n '/^hits/,$p' server-hits.log > server-hits.txt
  $ grep -E '^(hits|statement|plugins)|User Error|Error when' server-hits.txt
  hits: copy 3
  statement results complete: false
  plugins.eva.ast.getDeadCode: refused: cannot classify the statements of copy as reached or unreachable: in the current analysis of Eva, a hit of the cache answered a call of this function without analysing its body, and saved no state at its statements
  [studia] User Error: cannot find the statements that access a location: in the current analysis of Eva, a hit of the cache answered a call without analysing the body of the called function, and saved no state at its statements
  plugins.studia.studia.getReadsLval: refused
  [studia] User Error: cannot find the statements that access a location: in the current analysis of Eva, a hit of the cache answered a call without analysing the body of the called function, and saved no state at its statements
  plugins.studia.studia.getWritesLval: refused
  $ EVA_TEST_CACHE_PARTS_SERVER=loaded frama-c -no-autoload-plugins -load-module eva,eva.server_api,from,inout,test_cache_parts_server.cmxs -load hits.sav > server.log 2>&1
  $ grep -E '^(statement|plugins)|User Error|Error when' server.log
  statement results complete: false
  plugins.eva.ast.getDeadCode: refused: cannot classify the statements of copy as reached or unreachable: in the current analysis of Eva, a hit of the cache answered a call of this function without analysing its body, and saved no state at its statements
  [studia] User Error: cannot find the statements that access a location: in the current analysis of Eva, a hit of the cache answered a call without analysing the body of the called function, and saved no state at its statements
  plugins.studia.studia.getReadsLval: refused
  [studia] User Error: cannot find the statements that access a location: in the current analysis of Eva, a hit of the cache answered a call without analysing the body of the called function, and saved no state at its statements
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

The results of Eva at the statements of a function answered by hits are
not delivered, and only the readers above refuse them: the first statement
of copy is reachable with caching disabled, and not after the hits. This is
the work of the issue of the reachable statements.

  $ EVA_TEST_CACHE_PARTS=raw frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > raw.log 2>&1
  $ grep -E 'reachable' raw.log
  caching disabled: first statement of copy reachable: true
  after the hits: first statement of copy reachable: false

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
