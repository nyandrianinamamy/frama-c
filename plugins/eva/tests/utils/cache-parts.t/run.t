Parts of cache entries owned by From and Inout. In each scenario, a first
analysis with caching disabled produces the entries of the callees of
parts.c, which are then supplied to a second analysis. The test module
prints the parts of each entry and compares the two analyses.

  $ dune build -j 8 --cache=disabled --root . test_cache_parts.cmxs

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

Three requests of the server, after an analysis with caching disabled and
after the analysis with hits: the dead code of copy, and the statements
that read and that write b at the first call to copy, which Studia, loaded
after the analysis, computes with Inout. After the hits, no statement of
copy is reported as reached or unreachable, and Studia's requests are
refused.

  $ EVA_TEST_CACHE_PARTS=server-fresh frama-c -no-autoload-plugins -load-module eva,eva.server_api,from,inout,test_cache_parts.cmxs parts.c > server-fresh.log 2>&1
  $ grep -E '^plugins' server-fresh.log
  plugins.eva.ast.getDeadCode: unreachable 0, reached 2, nonTerminating 0
  plugins.studia.studia.getReadsLval: indirect 4, direct 1
  plugins.studia.studia.getWritesLval: indirect 0, direct 1
  $ EVA_TEST_CACHE_PARTS=server frama-c -no-autoload-plugins -load-module eva,eva.server_api,from,inout,test_cache_parts.cmxs parts.c > server.log 2>&1
  $ grep -E '^(hits|plugins)|User Error|Error when' server.log
  hits: copy 3; statement results complete: false
  plugins.eva.ast.getDeadCode: unreachable 0, reached 0, nonTerminating 0
  [studia] User Error: cannot find the statements that access a location: in the current analysis of Eva, a hit of the cache answered a call without analysing the body of the called function, and saved no state at its statements
  plugins.studia.studia.getReadsLval: refused
  [studia] User Error: cannot find the statements that access a location: in the current analysis of Eva, a hit of the cache answered a call without analysing the body of the called function, and saved no state at its statements
  plugins.studia.studia.getWritesLval: refused

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

A value of a part is kept with the entry only when it is given for the body
being analysed, in the project current when its analysis started. The test
module registers three parts and gives a value of each during the analysis
of copy: for its callstack, for its callstack while another project is
current, and for the callstack of its caller.

  $ EVA_TEST_CACHE_PARTS=project frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > project.log 2>&1
  $ grep '^entry of' project.log
  entry of copy: parts [inout, kept]
  entry of copy: parts [inout, kept]
  entry of copy: parts [inout, kept]
  entry of narrow: parts [inout]
  entry of narrow_and_write: parts [inout]
  entry of checked: parts [inout]
  entry of checked: parts [inout]

Entries are supplied to the project in which they were produced. A copy of
this project, made by Project.create_by_copy, has other values for its
functions, and the supply refuses the entries.

  $ EVA_TEST_CACHE_PARTS=copied frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > copied.log 2>&1
  $ grep -E 'supplied|refused|internal error' copied.log
  refused: Supplied_entries: the function copy of the entry is not a function of the current project; entries are supplied to the project whose AST they were made on
