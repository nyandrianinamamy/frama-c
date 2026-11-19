The Reach part of a cache entry holds the guard outcomes, the zones read and
written at each statement, the call sites of the calls its body makes and,
if the analysis saved the states of the body, the statements it reaches. A
hit delivers them at its own callstack. The test module prints, for the
statements of body, what the readers of the results see: the callstacks
with a state before and after each statement, the classification of the
server request of dead code computed from the same queries, the statuses,
the guard outcomes, the call sites of body and the zones. These lines start
with "| " and are sorted, to compare two runs.

  $ dune build -j 8 --cache=disabled --root . test_cache_reach.cmxs test_dead_code.cmxs

A first analysis from producer analyses body(1) and stores its entry. At
x = 1, the branch of x == 1 is taken and the branch of x == 3 is not: the
part holds the then outcome of the first condition, the else outcome of the
second, the states before and after the seven statements reached, and the
zones of five of them. Each write belongs to the body, with no frame above
it.

  $ EVA_TEST_CACHE_REACH=replay EVA_TEST_CACHE_REACH_VALUES=on frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-msg-key cache reach.c -save replay.sav > replay.log 2>&1
  $ grep '^part: ' replay.log
  part: guard reach.c:14 (stmt 8): else
  part: guard reach.c:8 (stmt 3): then
  part: reached after reach.c:10 (stmt 5), in the body
  part: reached after reach.c:14 (stmt 8), in the body
  part: reached after reach.c:18 (stmt 12), in the body
  part: reached after reach.c:19 (stmt 22), in the body
  part: reached after reach.c:7 (stmt 1), in the body
  part: reached after reach.c:8 (stmt 3), in the body
  part: reached after reach.c:9 (stmt 4), in the body
  part: reached before reach.c:10 (stmt 5), in the body
  part: reached before reach.c:14 (stmt 8), in the body
  part: reached before reach.c:18 (stmt 12), in the body
  part: reached before reach.c:19 (stmt 22), in the body
  part: reached before reach.c:7 (stmt 1), in the body
  part: reached before reach.c:8 (stmt 3), in the body
  part: reached before reach.c:9 (stmt 4), in the body
  part: zones at reach.c:10 (stmt 5), read \nothing, write out, in the body
  part: zones at reach.c:14 (stmt 8), read x, write \nothing, in the body
  part: zones at reach.c:18 (stmt 12), read x; l, write g, in the body
  part: zones at reach.c:7 (stmt 1), read \nothing, write l, in the body
  part: zones at reach.c:8 (stmt 3), read x, write \nothing, in the body

Changing the entry point to main resets the analysis, and the second
analysis is given the entry. body(2) has another key and is analysed;
body(1) at line 30 is a hit. The callstack of line 30 reaches body only
through the hit.

  $ grep -E 'call to body|statements reached' replay.log
    call to body: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: would-store
    In these functions, 9 statements reached (out of 12): 75% coverage.
    call to body: lookup: rejected (entry 1: key-differs); execution: analysed; storage: refused (supplied-only); collector: would-store
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
    In these functions, 12 statements reached (out of 14): 86% coverage.

Results of the second analysis. The statements of the branch of x == 1
(lines 9 and 10) are reached in the callstack of line 30 only, and the
statements reached by both calls are reached in both callstacks. Only the
branch of x == 3, which no call reaches, is unreachable: its assertion is
valid and its statement gets the reachability status invalid. The condition
of line 8 has both outcomes, then from the hit. main calls body at lines 29
and 30. The zones of the callstack of line 30 come from the hit, the zone of
line 10 from it alone.

  $ grep '^| ' replay.log > replay.summary
  $ cat replay.summary
  | call sites of body: main at line 29, main at line 30
  | dead code: stmt 1 (line 7): reached
  | dead code: stmt 10 (line 16): unreachable
  | dead code: stmt 12 (line 18): reached
  | dead code: stmt 22 (line 19): reached
  | dead code: stmt 3 (line 8): reached
  | dead code: stmt 4 (line 9): reached
  | dead code: stmt 5 (line 10): reached
  | dead code: stmt 6 (line 12): reached
  | dead code: stmt 8 (line 14): reached
  | dead code: stmt 9 (line 15): unreachable
  | guard: stmt 3 (line 8): then true, else true
  | guard: stmt 8 (line 14): then false, else true
  | reach.c:15: status of reachability of stmt reach.c:15 in body: invalid and reachable
  | reach.c:15: status of three: valid
  | reach.c:9: status of one: valid
  | reach: stmt 1 (line 7): before in body :: line 29 <- main, body :: line 30 <- main; after in body :: line 29 <- main, body :: line 30 <- main
  | reach: stmt 10 (line 16): before in none; after in none
  | reach: stmt 12 (line 18): before in body :: line 29 <- main, body :: line 30 <- main; after in body :: line 29 <- main, body :: line 30 <- main
  | reach: stmt 22 (line 19): before in body :: line 29 <- main, body :: line 30 <- main; after in body :: line 29 <- main, body :: line 30 <- main
  | reach: stmt 3 (line 8): before in body :: line 29 <- main, body :: line 30 <- main; after in body :: line 29 <- main, body :: line 30 <- main
  | reach: stmt 4 (line 9): before in body :: line 30 <- main; after in body :: line 30 <- main
  | reach: stmt 5 (line 10): before in body :: line 30 <- main; after in body :: line 30 <- main
  | reach: stmt 6 (line 12): before in body :: line 29 <- main; after in body :: line 29 <- main
  | reach: stmt 8 (line 14): before in body :: line 29 <- main, body :: line 30 <- main; after in body :: line 29 <- main, body :: line 30 <- main
  | reach: stmt 9 (line 15): before in none; after in none
  | zones: stmt 1 (line 7) in body :: line 29 <- main: read \nothing; write l
  | zones: stmt 1 (line 7) in body :: line 30 <- main: read \nothing; write l
  | zones: stmt 12 (line 18) in body :: line 29 <- main: read x; l; write g
  | zones: stmt 12 (line 18) in body :: line 30 <- main: read x; l; write g
  | zones: stmt 3 (line 8) in body :: line 29 <- main: read x; write \nothing
  | zones: stmt 3 (line 8) in body :: line 30 <- main: read x; write \nothing
  | zones: stmt 5 (line 10) in body :: line 30 <- main: read \nothing; write out
  | zones: stmt 6 (line 12) in body :: line 29 <- main: read \nothing; write out
  | zones: stmt 8 (line 14) in body :: line 29 <- main: read x; write \nothing
  | zones: stmt 8 (line 14) in body :: line 30 <- main: read x; write \nothing

The same program with caching disabled gives the same lines, and the same
coverage in the summary of the analysis.

  $ EVA_TEST_CACHE_REACH=reference EVA_TEST_CACHE_REACH_VALUES=on frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -eva-msg-key cache reach.c -save reference.sav > reference.log 2>&1
  $ grep '^| ' reference.log > reference.summary
  $ diff replay.summary reference.summary
  $ grep 'statements reached' reference.log
    In these functions, 12 statements reached (out of 14): 86% coverage.

A hit saves no state: a statement reached through it has the state top in
its callstack, and the states of all callstacks are joined into top. With
caching disabled, x is 1 in the callstack of line 30. A reader that draws a
conclusion from the values at these statements draws none.

  $ grep -E '^(hits|reachability|value)' replay.log
  hits on body: 1
  reachability of body unknown: false
  value of x before stmt 12 (line 18): {{ ANYTHING }}
  value of x before stmt 12 (line 18) in body :: line 29 <- main: {2}
  value of x before stmt 12 (line 18) in body :: line 30 <- main: {{ ANYTHING }}
  $ grep -E '^(hits|reachability|value)' reference.log
  hits on body: 0
  reachability of body unknown: false
  value of x before stmt 12 (line 18): {1; 2}
  value of x before stmt 12 (line 18) in body :: line 29 <- main: {2}
  value of x before stmt 12 (line 18) in body :: line 30 <- main: {1}

The statements reached through a hit are saved with the analysis, and read
again after -load without a new analysis.

  $ EVA_TEST_CACHE_REACH=loaded frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -load replay.sav > loaded.log 2>&1
  $ grep -E '^(hits|reachability)' loaded.log
  hits on body: 1
  reachability of body unknown: false
  $ grep '^| ' loaded.log > loaded.summary
  $ diff replay.summary loaded.summary

The server request of dead code, sent by a second process that loads the
session, gives the same response after the analysis with the hit as with
caching disabled. The test module test_dead_code prints the statements of
the response in the source syntax.

  $ frama-c -no-autoload-plugins -load-module server,eva,eva.server_api,test_dead_code.cmxs -load replay.sav > replay.server 2>&1
  $ frama-c -no-autoload-plugins -load-module server,eva,eva.server_api,test_dead_code.cmxs -load reference.sav > reference.server 2>&1
  $ diff replay.server reference.server
  $ cat replay.server
  getDeadCode body:
    { unreachable: [ out = 3;, ; ],
      reached: [ return;,
                 g = x + l;,
                 if (x == 3) {   ;   out = 3; },
                 out = 2;,
                 out = 1;,
                 ;,
                 if (x == 1) {   ;   out = 1; } else out = 2;,
                 int l = 1; ],
      nonTerminating: [] }

Eva_results.get_results takes the results of the current analysis, and
Eva_results.set_results clears the results and installs those it is given.
With RESTORE=same, the test module takes the results and installs them in
the same project, then prints its lines again, prefixed by "restored ". The
points reached by the hit, and the record that it skipped the visits of
body, are installed with the states: the callstacks, the dead code, the
values and the annotations that Export generates in body are those before.
The number of hits is a statistic, not a result, and is 0
after the installation. The results hold neither the guard outcomes, nor
the zones, nor the statuses of reachability: they are lost, with or without
the hit.

  $ EVA_TEST_CACHE_REACH=replay EVA_TEST_CACHE_REACH_RESTORE=same EVA_TEST_CACHE_REACH_VALUES=on EVA_TEST_CACHE_REACH_EXPORT=on frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-msg-key cache reach.c > restore.log 2>&1
  $ grep -E '^(hits|reachability|visits|points|value|exported|\| )' restore.log > restore.before
  $ sed -n 's/^restored //p' restore.log > restore.after
  $ diff restore.before restore.after
  1c1,2
  < hits on body: 1
  ---
  > results computed: true
  > hits on body: 0
  20,22c21,22
  < | guard: stmt 3 (line 8): then true, else true
  < | guard: stmt 8 (line 14): then false, else true
  < | reach.c:15: status of reachability of stmt reach.c:15 in body: invalid and reachable
  ---
  > | guard: stmt 3 (line 8): then false, else false
  > | guard: stmt 8 (line 14): then false, else false
  35,44d34
  < | zones: stmt 1 (line 7) in body :: line 29 <- main: read \nothing; write l
  < | zones: stmt 1 (line 7) in body :: line 30 <- main: read \nothing; write l
  < | zones: stmt 12 (line 18) in body :: line 29 <- main: read x; l; write g
  < | zones: stmt 12 (line 18) in body :: line 30 <- main: read x; l; write g
  < | zones: stmt 3 (line 8) in body :: line 29 <- main: read x; write \nothing
  < | zones: stmt 3 (line 8) in body :: line 30 <- main: read x; write \nothing
  < | zones: stmt 5 (line 10) in body :: line 30 <- main: read \nothing; write out
  < | zones: stmt 6 (line 12) in body :: line 29 <- main: read \nothing; write out
  < | zones: stmt 8 (line 14) in body :: line 29 <- main: read x; write \nothing
  < | zones: stmt 8 (line 14) in body :: line 30 <- main: read x; write \nothing
  [1]
  $ grep -E '^(restored )?visits' restore.log
  visits of body skipped: true
  restored visits of body skipped: true

The lines of the readers in the installed results with the hit (prefixed
"restored | ") equal those with caching disabled. As before the
installation, the values of x and the record of skipped visits differ, and
Export generates fewer annotations with the hit: the states of the hit
callstack are top. Each annotation it generates is also generated with
caching disabled.

  $ EVA_TEST_CACHE_REACH=reference EVA_TEST_CACHE_REACH_RESTORE=same EVA_TEST_CACHE_REACH_EXPORT=on frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -eva-msg-key cache reach.c > restore-reference.log 2>&1
  $ grep '^restored | ' restore.log > restore.summary
  $ grep '^restored | ' restore-reference.log > restore-reference.summary
  $ diff restore.summary restore-reference.summary
  $ grep '^restored exported' restore.log
  restored exported before line 15: assert Eva_export: \false;
  $ grep '^restored exported' restore-reference.log
  restored exported before line 8: assert Eva_export: 1 ≤ x ≤ 2;
  restored exported before line 14: assert Eva_export: 1 ≤ x ≤ 2;
  restored exported before line 15: assert Eva_export: \false;
  restored exported before line 18: assert Eva_export: l ≡ 1;
  restored exported before line 18: assert Eva_export: 1 ≤ x ≤ 2;

With RESTORE=copy, the test module takes the results in a copy of the
project and installs them there, then prints its lines in the original
project, prefixed by "original ". The installation in the copy gives the
lines of the installation in the same project, and leaves the original
project as it was.

  $ EVA_TEST_CACHE_REACH=replay EVA_TEST_CACHE_REACH_RESTORE=copy EVA_TEST_CACHE_REACH_VALUES=on EVA_TEST_CACHE_REACH_EXPORT=on frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-msg-key cache reach.c > restore-copy.log 2>&1
  $ sed -n 's/^restored //p' restore-copy.log > copy.after
  $ diff restore.after copy.after
  $ sed -n 's/^original //p' restore-copy.log > copy.original
  $ diff restore.before copy.original

In passes.c, main calls body(2, 1), which is analysed, then body(1, 0), a
hit. The division of line 13 is by 0 in the call of the hit. With
REFINE=on, the refinement of the statuses of alarms runs on the installed
results: the statement of line 13 is reached in the hit callstack, and the
alarm stays unknown, as with caching disabled.

  $ EVA_TEST_CACHE_REACH=replay EVA_TEST_CACHE_REACH_RESTORE=same EVA_TEST_CACHE_REACH_REFINE=on frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-msg-key cache passes.c > refine.log 2>&1
  $ grep -E 'call to body' refine.log
    call to body: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: would-store
    call to body: lookup: rejected (entry 1: key-differs); execution: analysed; storage: refused (supplied-only); collector: would-store
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  $ grep -E '^(restored )?\| passes.c:13' refine.log
  | passes.c:13: status of Eva: unknown
  restored | passes.c:13: status of Eva: unknown
  $ EVA_TEST_CACHE_REACH=reference EVA_TEST_CACHE_REACH_RESTORE=same EVA_TEST_CACHE_REACH_REFINE=on frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -eva-msg-key cache passes.c > refine-reference.log 2>&1
  $ grep '^restored | ' refine.log > refine.summary
  $ grep '^restored | ' refine-reference.log > refine-reference.summary
  $ diff refine.summary refine-reference.summary

An entry without a Reach part: the same entry supplied by hand without it.
A hit delivers the Reach part of its entry, and the lookup rejects an entry
without one (missing-points), whatever the states that the analysis saves:
body is analysed. The lines of the readers, the values of x, the
annotations that Export generates, the lines after the results are taken
and installed again (RESTORE=same) and the response of the server request
of dead code on the session saved after that equal those of caching
disabled.

  $ EVA_TEST_CACHE_REACH=replay EVA_TEST_CACHE_REACH_PART=drop EVA_TEST_CACHE_REACH_VALUES=on EVA_TEST_CACHE_REACH_RESTORE=same EVA_TEST_CACHE_REACH_EXPORT=on frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-msg-key cache reach.c -save drop.sav > drop.log 2>&1
  $ grep -E 'call to body|statements reached' drop.log
    call to body: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: would-store
    In these functions, 9 statements reached (out of 12): 75% coverage.
    call to body: lookup: rejected (entry 1: key-differs); execution: analysed; storage: refused (supplied-only); collector: would-store
    call to body: lookup: rejected (entry 1: missing-points); execution: analysed; storage: refused (supplied-only); collector: would-store
    In these functions, 12 statements reached (out of 14): 86% coverage.
  $ EVA_TEST_CACHE_REACH=reference EVA_TEST_CACHE_REACH_VALUES=on EVA_TEST_CACHE_REACH_RESTORE=same EVA_TEST_CACHE_REACH_EXPORT=on frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -eva-msg-key cache reach.c -save drop-reference.sav > drop-reference.log 2>&1
  $ grep 'statements reached' drop-reference.log
    In these functions, 12 statements reached (out of 14): 86% coverage.
  $ grep -E '^(restored )?(results|hits|reachability|visits|points|value|exported|\| )' drop.log > drop.observed
  $ grep -E '^(restored )?(results|hits|reachability|visits|points|value|exported|\| )' drop-reference.log > drop-reference.observed
  $ diff drop.observed drop-reference.observed
  $ frama-c -no-autoload-plugins -load-module server,eva,eva.server_api,test_dead_code.cmxs -load drop.sav > drop.server 2>&1
  $ frama-c -no-autoload-plugins -load-module server,eva,eva.server_api,test_dead_code.cmxs -load drop-reference.sav > drop-reference.server 2>&1
  $ diff drop.server drop-reference.server

The analysis of a body makes the guard outcomes, the zones and the call
sites whether or not it saves the states of the body, and reaches points
only when it saves them. With PRODUCER=body, the first analysis saves no
state of body (as -eva-no-results-function body): the Reach part of the
entry has no points. The second analysis saves the states of body, and a
hit would leave the statements of body without a state in its callstack:
the lookup rejects the entry (missing-points), and body is analysed. The
results equal those of caching disabled.

  $ EVA_TEST_CACHE_REACH=replay EVA_TEST_CACHE_REACH_PRODUCER=body frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-msg-key cache reach.c > producer-body.log 2>&1
  $ grep -E '^(part|points of the part)' producer-body.log
  part: guard reach.c:14 (stmt 8): else
  part: guard reach.c:8 (stmt 3): then
  part: zones at reach.c:10 (stmt 5), read \nothing, write out, in the body
  part: zones at reach.c:14 (stmt 8), read x, write \nothing, in the body
  part: zones at reach.c:18 (stmt 12), read x; l, write g, in the body
  part: zones at reach.c:7 (stmt 1), read \nothing, write l, in the body
  part: zones at reach.c:8 (stmt 3), read x, write \nothing, in the body
  points of the part: not recorded
  $ grep -E 'call to body' producer-body.log
    call to body: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: would-store
    call to body: lookup: rejected (entry 1: key-differs); execution: analysed; storage: refused (supplied-only); collector: would-store
    call to body: lookup: rejected (entry 1: missing-points); execution: analysed; storage: refused (supplied-only); collector: would-store
  $ grep '^| ' producer-body.log > producer-body.summary
  $ diff producer-body.summary reference.summary

The same with PRODUCER=global, where the first analysis saves no state at
all (as -eva-no-results), and with PART=nopoints, where the entry is
supplied by hand with its Reach part without the points.

  $ EVA_TEST_CACHE_REACH=replay EVA_TEST_CACHE_REACH_PRODUCER=global frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-msg-key cache reach.c > producer-global.log 2>&1
  $ grep -E '^points of the part|lookup: rejected' producer-global.log
  points of the part: not recorded
    call to body: lookup: rejected (entry 1: key-differs); execution: analysed; storage: refused (supplied-only); collector: would-store
    call to body: lookup: rejected (entry 1: missing-points); execution: analysed; storage: refused (supplied-only); collector: would-store
  $ grep '^| ' producer-global.log > producer-global.summary
  $ diff producer-global.summary reference.summary
  $ EVA_TEST_CACHE_REACH=replay EVA_TEST_CACHE_REACH_PART=nopoints frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-msg-key cache reach.c > nopoints.log 2>&1
  $ grep -E 'lookup: rejected' nopoints.log
    call to body: lookup: rejected (entry 1: key-differs); execution: analysed; storage: refused (supplied-only); collector: would-store
    call to body: lookup: rejected (entry 1: missing-points); execution: analysed; storage: refused (supplied-only); collector: would-store
  $ grep '^| ' nopoints.log > nopoints.summary
  $ diff nopoints.summary reference.summary

A rejection for missing-points does not end the lookup: the next candidate
is examined. With SECOND=on, the produced entry is supplied after the entry
written by hand, with its Reach part without the points (PART=nopoints) or
without it (PART=drop), and answers the call at line 30. The lines equal
those of caching disabled.

  $ EVA_TEST_CACHE_REACH=replay EVA_TEST_CACHE_REACH_PART=nopoints EVA_TEST_CACHE_REACH_SECOND=on frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-msg-key cache reach.c > second-nopoints.log 2>&1
  $ grep 'missing-points' second-nopoints.log
    call to body: lookup: rejected (entry 1: missing-points), hit (entry 2); execution: not-analysed; storage: none
  $ grep '^| ' second-nopoints.log > second-nopoints.summary
  $ diff second-nopoints.summary reference.summary
  $ EVA_TEST_CACHE_REACH=replay EVA_TEST_CACHE_REACH_PART=drop EVA_TEST_CACHE_REACH_SECOND=on frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-msg-key cache reach.c > second-drop.log 2>&1
  $ grep 'missing-points' second-drop.log
    call to body: lookup: rejected (entry 1: missing-points), hit (entry 2); execution: not-analysed; storage: none
  $ grep '^| ' second-drop.log > second-drop.summary
  $ diff second-drop.summary reference.summary

When neither analysis saves the states of body, as with
-eva-no-results-function body on the command line, the entry is a hit. It
delivers its guard outcomes, zones and call sites, and no point. The
results equal those of caching disabled under the same option.

  $ EVA_TEST_CACHE_REACH=replay frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-no-results-function body -eva-msg-key cache reach.c > both.log 2>&1
  $ grep -E '^(points of the part|hits|reachability|points of body)|lookup: hit' both.log
  points of the part: not recorded
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  hits on body: 1
  reachability of body unknown: false
  points of body reached by hits: 0
  $ grep '^| ' both.log > both.summary
  $ EVA_TEST_CACHE_REACH=reference frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -eva-no-results-function body -eva-msg-key cache reach.c > both-reference.log 2>&1
  $ grep '^| ' both-reference.log > both-reference.summary
  $ diff both.summary both-reference.summary
  $ cat both.summary
  | call sites of body: main at line 29, main at line 30
  | dead code: stmt 1 (line 7): unreachable
  | dead code: stmt 10 (line 16): unreachable
  | dead code: stmt 12 (line 18): unreachable
  | dead code: stmt 22 (line 19): unreachable
  | dead code: stmt 3 (line 8): unreachable
  | dead code: stmt 4 (line 9): unreachable
  | dead code: stmt 5 (line 10): unreachable
  | dead code: stmt 6 (line 12): unreachable
  | dead code: stmt 8 (line 14): unreachable
  | dead code: stmt 9 (line 15): unreachable
  | guard: stmt 3 (line 8): then true, else true
  | guard: stmt 8 (line 14): then false, else true
  | reach.c:9: status of one: valid
  | reach: stmt 1 (line 7): before in none; after in none
  | reach: stmt 10 (line 16): before in none; after in none
  | reach: stmt 12 (line 18): before in none; after in none
  | reach: stmt 22 (line 19): before in none; after in none
  | reach: stmt 3 (line 8): before in none; after in none
  | reach: stmt 4 (line 9): before in none; after in none
  | reach: stmt 5 (line 10): before in none; after in none
  | reach: stmt 6 (line 12): before in none; after in none
  | reach: stmt 8 (line 14): before in none; after in none
  | reach: stmt 9 (line 15): before in none; after in none
  | zones: stmt 1 (line 7) in body :: line 29 <- main: read \nothing; write l
  | zones: stmt 1 (line 7) in body :: line 30 <- main: read \nothing; write l
  | zones: stmt 12 (line 18) in body :: line 29 <- main: read x; l; write g
  | zones: stmt 12 (line 18) in body :: line 30 <- main: read x; l; write g
  | zones: stmt 3 (line 8) in body :: line 29 <- main: read x; write \nothing
  | zones: stmt 3 (line 8) in body :: line 30 <- main: read x; write \nothing
  | zones: stmt 5 (line 10) in body :: line 30 <- main: read \nothing; write out
  | zones: stmt 6 (line 12) in body :: line 29 <- main: read \nothing; write out
  | zones: stmt 8 (line 14) in body :: line 29 <- main: read x; write \nothing
  | zones: stmt 8 (line 14) in body :: line 30 <- main: read x; write \nothing

The same with -eva-no-results.

  $ EVA_TEST_CACHE_REACH=replay frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-no-results -eva-msg-key cache reach.c > global.log 2>&1
  $ grep -E '^(points of the part|hits|reachability|points of body)|lookup: hit' global.log
  points of the part: not recorded
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  hits on body: 1
  reachability of body unknown: false
  points of body reached by hits: 0
  $ grep '^| ' global.log > global.summary
  $ EVA_TEST_CACHE_REACH=reference frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -eva-no-results -eva-msg-key cache reach.c > global-reference.log 2>&1
  $ grep '^| ' global-reference.log > global-reference.summary
  $ diff global.summary global-reference.summary

With CONSUMER=body or CONSUMER=global, the first analysis saves the states
of body, and the second does not (as -eva-no-results-function body, or as
-eva-no-results). The entry is a hit, and its points are not delivered:
the results equal those of caching disabled under the same option.

  $ EVA_TEST_CACHE_REACH=replay EVA_TEST_CACHE_REACH_CONSUMER=body frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-msg-key cache reach.c > consumer-body.log 2>&1
  $ grep -E '^(hits|reachability|points of body)|lookup: hit' consumer-body.log
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  hits on body: 1
  reachability of body unknown: false
  points of body reached by hits: 0
  $ grep '^| ' consumer-body.log > consumer-body.summary
  $ diff consumer-body.summary both-reference.summary
  $ EVA_TEST_CACHE_REACH=replay EVA_TEST_CACHE_REACH_CONSUMER=global frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-msg-key cache reach.c > consumer-global.log 2>&1
  $ grep -E '^(hits|reachability|points of body)|lookup: hit' consumer-global.log
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  hits on body: 1
  reachability of body unknown: false
  points of body reached by hits: 0
  $ grep '^| ' consumer-global.log > consumer-global.summary
  $ diff consumer-global.summary global-reference.summary

The entry without a Reach part is rejected as well where the analysis that
uses it saves no state of body (CONSUMER=body) or none at all
(CONSUMER=global), and the lines equal those of caching disabled under the
same option: the guard of line 8 has its then outcome, and the callstack of
line 30 its zones.

  $ EVA_TEST_CACHE_REACH=replay EVA_TEST_CACHE_REACH_PART=drop EVA_TEST_CACHE_REACH_CONSUMER=body frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-msg-key cache reach.c > drop-body.log 2>&1
  $ grep -E 'missing-points|^(hits|reachability)' drop-body.log
    call to body: lookup: rejected (entry 1: missing-points); execution: analysed; storage: refused (supplied-only); collector: would-store
  hits on body: 0
  reachability of body unknown: false
  $ grep '^| ' drop-body.log > drop-body.summary
  $ diff drop-body.summary both-reference.summary
  $ EVA_TEST_CACHE_REACH=replay EVA_TEST_CACHE_REACH_PART=drop EVA_TEST_CACHE_REACH_CONSUMER=global frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-msg-key cache reach.c > drop-global.log 2>&1
  $ grep -E 'missing-points|^(hits|reachability)' drop-global.log
    call to body: lookup: rejected (entry 1: missing-points); execution: analysed; storage: refused (supplied-only); collector: would-store
  hits on body: 0
  reachability of body unknown: false
  $ grep '^| ' drop-global.log > drop-global.summary
  $ diff drop-global.summary global-reference.summary

With -eva-no-results-domain cvalue, the store of the states of the cvalue
domain saves no state, and the queries answer no callstack at any
statement. With caching disabled, every statement of body then reads as
unreachable, although body is called: the server request of dead code
lists them all, and Export generates the annotation \false before the
statements of lines 14 and 18. A hit delivers its points, which the
queries do not see: body is recorded as of unknown reachability, the
server request lists no statement of body, and Export generates no
annotation in body.

  $ EVA_TEST_CACHE_REACH=replay EVA_TEST_CACHE_REACH_EXPORT=on frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-no-results-domain cvalue -eva-msg-key cache reach.c -save domain.sav > domain.log 2>&1
  $ grep -E '^(hits|reachability|points of body|exported)|lookup: hit|statements reached' domain.log
    In these functions, 12 statements reached (out of 12): 100% coverage.
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
    In these functions, 14 statements reached (out of 14): 100% coverage.
  hits on body: 1
  reachability of body unknown: true
  points of body reached by hits: 14
  $ frama-c -no-autoload-plugins -load-module server,eva,eva.server_api,test_dead_code.cmxs -load domain.sav > domain.server 2>&1
  $ cat domain.server
  getDeadCode body:
    { unreachable: [], reached: [], nonTerminating: [] }
  $ EVA_TEST_CACHE_REACH=reference EVA_TEST_CACHE_REACH_EXPORT=on frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -eva-no-results-domain cvalue -eva-msg-key cache reach.c -save domain-reference.sav > domain-reference.log 2>&1
  $ grep -E '^(hits|reachability|points of body|exported)|statements reached' domain-reference.log
    In these functions, 14 statements reached (out of 14): 100% coverage.
  hits on body: 0
  reachability of body unknown: false
  points of body reached by hits: 0
  exported before line 14: assert Eva_export: \false;
  exported before line 18: assert Eva_export: \false;
  $ frama-c -no-autoload-plugins -load-module server,eva,eva.server_api,test_dead_code.cmxs -load domain-reference.sav > domain-reference.server 2>&1
  $ cat domain-reference.server
  getDeadCode body:
    { unreachable: [ return;,
                     g = x + l;,
                     out = 3;,
                     ;,
                     if (x == 3) {   ;   out = 3; },
                     out = 2;,
                     out = 1;,
                     ;,
                     if (x == 1) {   ;   out = 1; } else out = 2;,
                     int l = 1; ],
      reached: [],
      nonTerminating: [] }

The other lines, the guard outcomes, the zones and the call sites among
them, equal those of caching disabled.

  $ grep '^| ' domain.log > domain.summary
  $ grep '^| ' domain-reference.log > domain-reference.summary
  $ diff domain.summary domain-reference.summary

The record of unknown reachability is kept when the results are taken and
installed again (RESTORE=same), and in the session saved after that.

  $ EVA_TEST_CACHE_REACH=replay EVA_TEST_CACHE_REACH_RESTORE=same frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-no-results-domain cvalue -eva-msg-key cache reach.c -save domain-restore.sav > domain-restore.log 2>&1
  $ grep '^restored reachability' domain-restore.log
  restored reachability of body unknown: true
  $ frama-c -no-autoload-plugins -load-module server,eva,eva.server_api,test_dead_code.cmxs -load domain-restore.sav > domain-restore.server 2>&1
  $ diff domain-restore.server domain.server

In holder.c, body stores the address of its formal x into gp. After the
call, the caller ends the lifetime of x, and gp holds an escaping address.
The entry holds, with its result, the variables to which the body wrote the
address of a local or formal; at the hit at line 21, the caller finishes the
call with them, as after an analysis of the body. The results equal those
of caching disabled.

  $ EVA_TEST_CACHE_REACH=replay frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-msg-key cache holder.c > holder.log 2>&1
  $ grep -B 1 'lookup: hit' holder.log | sed 's/ *$//'
  [eva:cache] holder.c:21:
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  $ grep '^| ' holder.log > holder.summary
  $ EVA_TEST_CACHE_REACH=reference frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -eva-msg-key cache holder.c > holder-reference.log 2>&1
  $ grep '^| ' holder-reference.log > holder-reference.summary
  $ diff holder.summary holder-reference.summary
  $ grep -E 'end of main|call sites' holder.summary
  | end of main: gp = ESCAPINGADDR
  | call sites of body: main at line 20, main at line 21

In loop.c, with -eva-slevel 10, main calls body(2), then body(1), at the
same call site: the hit delivers its writes on the callstack of the
analysed call. The statements and the zone of the branch of x == 1 come
from the hit alone; the other zones and the outcomes of the condition are
joined with those of the analysed call. The results equal those of caching
disabled. In that callstack, the state of a statement that both calls
reach is top: it covers x = 2 from the analysed call and x = 1 from the
hit.

  $ EVA_TEST_CACHE_REACH=replay EVA_TEST_CACHE_REACH_VALUES=on frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-msg-key cache -eva-slevel 10 loop.c > loop.log 2>&1
  $ grep -E 'call to body|^value' loop.log
    call to body: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: would-store
    call to body: lookup: rejected (entry 1: key-differs); execution: analysed; storage: refused (supplied-only); collector: would-store
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  value of x before stmt 5 (line 13): {{ ANYTHING }}
  value of x before stmt 5 (line 13) in body :: line 23 <- main: {{ ANYTHING }}
  $ grep '^| ' loop.log > loop.summary
  $ EVA_TEST_CACHE_REACH=reference frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -eva-msg-key cache -eva-slevel 10 loop.c > loop-reference.log 2>&1
  $ grep '^| ' loop-reference.log > loop-reference.summary
  $ diff loop.summary loop-reference.summary
  $ cat loop.summary
  | call sites of body: main at line 23
  | dead code: stmt 2 (line 8): reached
  | dead code: stmt 22 (line 14): reached
  | dead code: stmt 3 (line 9): reached
  | dead code: stmt 4 (line 11): reached
  | dead code: stmt 5 (line 13): reached
  | guard: stmt 2 (line 8): then true, else true
  | reach: stmt 2 (line 8): before in body :: line 23 <- main; after in body :: line 23 <- main
  | reach: stmt 22 (line 14): before in body :: line 23 <- main; after in body :: line 23 <- main
  | reach: stmt 3 (line 9): before in body :: line 23 <- main; after in body :: line 23 <- main
  | reach: stmt 4 (line 11): before in body :: line 23 <- main; after in body :: line 23 <- main
  | reach: stmt 5 (line 13): before in body :: line 23 <- main; after in body :: line 23 <- main
  | zones: stmt 2 (line 8) in body :: line 23 <- main: read x; write \nothing
  | zones: stmt 3 (line 9) in body :: line 23 <- main: read \nothing; write out
  | zones: stmt 4 (line 11) in body :: line 23 <- main: read \nothing; write out
  | zones: stmt 5 (line 13) in body :: line 23 <- main: read x; write g

In escape.c, body stores its argument, the address of the local of mid,
into gp. The caller of body adds the holders of the entry to those of mid,
and when mid returns, gp holds an escaping address.

  $ EVA_TEST_CACHE_REACH=replay frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-msg-key cache escape.c > escape.log 2>&1
  $ grep -B 1 'lookup: hit' escape.log | sed 's/ *$//'
  [eva:cache] escape.c:13:
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  $ grep '^| ' escape.log > escape.summary
  $ EVA_TEST_CACHE_REACH=reference frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -eva-msg-key cache escape.c > escape-reference.log 2>&1
  $ grep '^| ' escape-reference.log > escape-reference.summary
  $ diff escape.summary escape-reference.summary
  $ grep -E 'end of main|call sites' escape.summary
  | end of main: gp = ESCAPINGADDR
  | call sites of body: mid at line 13

In enclosing.c, parent calls child. In the analysis from main, the entry of
child is stored. The Reach part of parent holds its own statements, the
start of child and the call site of child, with the call of child as frame;
it holds none of the writes made in the body of child, which is analysed
afresh and has its own part. In the analysis from parent, a hit answers the
call of child: the writes it delivers are recorded in the part of parent,
with the call of child as frame. No hit delivers the part of a body with a
call (nested-delivery).

  $ EVA_TEST_CACHE_REACH=enclosing frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -eva-msg-key cache enclosing.c > enclosing.log 2>&1
  $ grep -E '^(part of parent|second analysis|hits on)|lookup: hit' enclosing.log
  part of parent: caller site of child :: enclosing.c:12 (stmt 7)
  part of parent: reached after enclosing.c:12 (stmt 7), in the body
  part of parent: reached after enclosing.c:13 (stmt 15), in the body
  part of parent: reached before enclosing.c:12 (stmt 7), in the body
  part of parent: reached before enclosing.c:13 (stmt 15), in the body
  part of parent: reached start of child, in child :: enclosing.c:12 (stmt 7)
  part of parent: zones at enclosing.c:12 (stmt 7), read \nothing, write x, in the body
  second analysis
    call to child: lookup: hit (entry 1); execution: not-analysed; storage: none
  part of parent: caller site of child :: enclosing.c:12 (stmt 7)
  part of parent: guard enclosing.c:8 (stmt 2): then
  part of parent: reached after enclosing.c:12 (stmt 7), in the body
  part of parent: reached after enclosing.c:13 (stmt 15), in the body
  part of parent: reached after enclosing.c:8 (stmt 2), in child :: enclosing.c:12 (stmt 7)
  part of parent: reached after enclosing.c:8 (stmt 3), in child :: enclosing.c:12 (stmt 7)
  part of parent: reached after enclosing.c:9 (stmt 13), in child :: enclosing.c:12 (stmt 7)
  part of parent: reached before enclosing.c:12 (stmt 7), in the body
  part of parent: reached before enclosing.c:13 (stmt 15), in the body
  part of parent: reached before enclosing.c:8 (stmt 2), in child :: enclosing.c:12 (stmt 7)
  part of parent: reached before enclosing.c:8 (stmt 3), in child :: enclosing.c:12 (stmt 7)
  part of parent: reached before enclosing.c:9 (stmt 13), in child :: enclosing.c:12 (stmt 7)
  part of parent: reached start of child, in child :: enclosing.c:12 (stmt 7)
  part of parent: zones at enclosing.c:12 (stmt 7), read \nothing, write x, in the body
  part of parent: zones at enclosing.c:8 (stmt 2), read x, write \nothing, in child :: enclosing.c:12 (stmt 7)
  part of parent: zones at enclosing.c:8 (stmt 3), read x, write out, in child :: enclosing.c:12 (stmt 7)
  hits on child: 1

Three programs in which a hit joins what it delivers with what is already
recorded, with -eva-slevel 10. In twohits.c, two hits answer the calls of
lines 5 and 6: the statement of body is reached in both callstacks. In
zones.c, main calls body(2), which is analysed, then body(1), a hit, at the
same call site: the zone written at line 4 is second from the analysed call
and first from the hit. In loopread.c, the loop of body reads second, then
first, at line 7: the Reach part holds both. The results equal those of
caching disabled.

  $ EVA_TEST_CACHE_REACH=replay frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-msg-key cache -eva-slevel 10 twohits.c > twohits.log 2>&1
  $ grep -E 'lookup: hit|^\| reach: stmt 1 ' twohits.log
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  | reach: stmt 1 (line 2): before in body :: line 5 <- main, body :: line 6 <- main; after in body :: line 5 <- main, body :: line 6 <- main
  $ grep '^| ' twohits.log > twohits.summary
  $ EVA_TEST_CACHE_REACH=reference frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -eva-msg-key cache -eva-slevel 10 twohits.c > twohits-reference.log 2>&1
  $ grep '^| ' twohits-reference.log > twohits-reference.summary
  $ diff twohits.summary twohits-reference.summary
  $ EVA_TEST_CACHE_REACH=replay frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-msg-key cache -eva-slevel 10 zones.c > zones.log 2>&1
  $ grep -E 'lookup: hit|^\| zones: stmt 8 ' zones.log
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  | zones: stmt 8 (line 4) in body :: line 8 <- main: read x; p; write first; second
  $ grep '^| ' zones.log > zones.summary
  $ EVA_TEST_CACHE_REACH=reference frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -eva-msg-key cache -eva-slevel 10 zones.c > zones-reference.log 2>&1
  $ grep '^| ' zones-reference.log > zones-reference.summary
  $ diff zones.summary zones-reference.summary

With the collector of block accesses enabled, the body of main is under
observation when the hit delivers its zones. With COLLECT=off, the collector
is disabled after the entry is produced and before the analysis from main,
and no body is under observation at the hit: the zones written at line 4
are still first and second, as with caching disabled.

  $ EVA_TEST_CACHE_REACH=replay EVA_TEST_CACHE_REACH_COLLECT=off frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-msg-key cache -eva-slevel 10 zones.c > zones-off.log 2>&1
  $ grep -E 'lookup: hit|^\| zones: stmt 8 ' zones-off.log
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  | zones: stmt 8 (line 4) in body :: line 8 <- main: read x; p; write first; second
  $ grep '^| ' zones-off.log > zones-off.summary
  $ diff zones-off.summary zones-reference.summary
  $ EVA_TEST_CACHE_REACH=replay frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-msg-key cache -eva-slevel 10 loopread.c > loopread.log 2>&1
  $ grep -E 'lookup: hit|^part: zones at loopread.c:7|^\| zones: stmt 12 ' loopread.log
  part: zones at loopread.c:7 (stmt 12), read first; second; p, write sink, in the body
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  | zones: stmt 12 (line 7) in body :: line 12 <- main: read first; second; p; write sink
  $ grep '^| ' loopread.log > loopread.summary
  $ EVA_TEST_CACHE_REACH=reference frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -eva-msg-key cache -eva-slevel 10 loopread.c > loopread-reference.log 2>&1
  $ grep '^| ' loopread-reference.log > loopread-reference.summary
  $ diff loopread.summary loopread-reference.summary
