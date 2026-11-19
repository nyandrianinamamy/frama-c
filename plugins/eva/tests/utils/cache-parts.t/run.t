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

With -eva, Eva also analyses the program before the test module does, and
prints the final states after each of the three analyses, filtered by the
outputs that Inout computes by function. An analysed caller of a hit has
the same final state as with caching disabled. A function answered by hits
only has no state saved, and its final state is not printed.

  $ EVA_TEST_CACHE_PARTS=inout frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs -eva parts.c > display.log 2>&1
  $ grep -o 'Values at end of function [a-z_]*' display.log | sort | uniq -c
        2 Values at end of function checked
        2 Values at end of function copy
        3 Values at end of function deps_main
        3 Values at end of function inout_main
        3 Values at end of function main
        2 Values at end of function narrow
        2 Values at end of function narrow_and_write
  $ grep -A3 'Values at end of function inout_main' display.log
  [eva:final-states] Values at end of function inout_main:
    g ∈ {5}
    h ∈ {7}
    out ∈ {5}
  --
  [eva:final-states] Values at end of function inout_main:
    g ∈ {5}
    h ∈ {7}
    out ∈ {5}
  --
  [eva:final-states] Values at end of function inout_main:
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
candidate when they are loaded.

  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,pdg,test_cache_parts.cmxs parts.c > pdg.log 2>&1
  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,impact,test_cache_parts.cmxs parts.c > impact.log 2>&1
  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,reduc,test_cache_parts.cmxs parts.c > reduc.log 2>&1
  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,scope,test_cache_parts.cmxs parts.c > scope.log 2>&1
  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,security_slicing,test_cache_parts.cmxs parts.c > security_slicing.log 2>&1
  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,slicing,test_cache_parts.cmxs parts.c > slicing.log 2>&1
  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,sparecode,test_cache_parts.cmxs parts.c > sparecode.log 2>&1
  $ EVA_TEST_CACHE_PARTS=readers frama-c -no-autoload-plugins -load-module eva,from,inout,studia,test_cache_parts.cmxs parts.c > studia.log 2>&1
  $ grep '^hits' pdg.log impact.log reduc.log scope.log security_slicing.log slicing.log sparecode.log studia.log
  pdg.log:hits 0, rejected for consumer 15
  impact.log:hits 0, rejected for consumer 15
  reduc.log:hits 0, rejected for consumer 15
  scope.log:hits 0, rejected for consumer 15
  security_slicing.log:hits 0, rejected for consumer 15
  slicing.log:hits 0, rejected for consumer 15
  sparecode.log:hits 0, rejected for consumer 15
  studia.log:hits 0, rejected for consumer 15

A request that the module supplying the entries makes itself, after the
analysis, is not detected. The results by function of copy, answered by
hits only, and of its caller deps_main miss the effects of copy.

  $ EVA_TEST_CACHE_PARTS=api frama-c -no-autoload-plugins -load-module eva,from,inout,test_cache_parts.cmxs parts.c > api.log 2>&1
  $ grep -E '^(hits|caching disabled|after the hits)' api.log
  hits: copy 3
  caching disabled: copy: from [a FROM indirect: dst; src; direct: b; d (or UNASSIGNED); c FROM indirect: dst; src; direct: b; d (or UNASSIGNED); \result FROM \nothing]; inputs [b; d; dst; src]
  caching disabled: deps_main: from [a FROM direct: b; d (or UNASSIGNED); c FROM direct: b; d (or UNASSIGNED); \result FROM \nothing]; inputs [b; d; dst; src]
  after the hits: copy: from [FROMUNREACHABLE; \result FROM \nothing]; inputs [\nothing]
  after the hits: deps_main: from [FROMUNREACHABLE; \result FROM \nothing]; inputs [\nothing]

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
