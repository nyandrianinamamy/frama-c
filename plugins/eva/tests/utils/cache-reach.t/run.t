The Reach part of a cache entry holds the statements its body reaches, the
guard outcomes, the zones read and written at each statement, and the call
sites of the calls it makes. A hit delivers them at its own callstack. The
test module prints, for the statements of body, what the readers of the
results see: the callstacks with a state before and after each statement,
the classification of the server request of dead code computed from the same
queries, the statuses, the guard outcomes, the call sites of body and the
zones. These lines start with "| " and are sorted, to compare two runs.

  $ dune build -j 8 --cache=disabled --root . test_cache_reach.cmxs

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

  $ EVA_TEST_CACHE_REACH=reference EVA_TEST_CACHE_REACH_VALUES=on frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -eva-msg-key cache reach.c > reference.log 2>&1
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

An entry without a Reach part: the same entry supplied by hand without it.
A hit on it delivers no statement, guard, zone or call site, and the
reachability of the statements of body is unknown. The marking of dead code
then marks nothing unreachable in body, the summary gives the coverage as a
range, and the server request of dead code returns no statement for body
(not shown: the lines below are computed from the queries the request
uses). The lines that differ from caching disabled are those of the hit.

  $ EVA_TEST_CACHE_REACH=replay EVA_TEST_CACHE_REACH_PART=drop frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-msg-key cache reach.c > drop.log 2>&1
  $ grep -E '^(hits|reachability)|lookup: hit|statements reached|answered by the cache' drop.log
    In these functions, 9 statements reached (out of 12): 75% coverage.
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
    In these functions, 10 statements reached (out of 14): 71% coverage,
    and up to 4 more through calls answered by the cache (100% coverage).
  hits on body: 1
  reachability of body unknown: true
  $ grep '^| ' drop.log > drop.summary
  $ diff drop.summary reference.summary
  7,8c7,8
  < | dead code: stmt 4 (line 9): unreachable
  < | dead code: stmt 5 (line 10): unreachable
  ---
  > | dead code: stmt 4 (line 9): reached
  > | dead code: stmt 5 (line 10): reached
  12c12
  < | guard: stmt 3 (line 8): then false, else true
  ---
  > | guard: stmt 3 (line 8): then true, else true
  13a14,15
  > | reach.c:15: status of reachability of stmt reach.c:15 in body: invalid and reachable
  > | reach.c:15: status of three: valid
  15c17
  < | reach: stmt 1 (line 7): before in body :: line 29 <- main; after in body :: line 29 <- main
  ---
  > | reach: stmt 1 (line 7): before in body :: line 29 <- main, body :: line 30 <- main; after in body :: line 29 <- main, body :: line 30 <- main
  17,21c19,23
  < | reach: stmt 12 (line 18): before in body :: line 29 <- main; after in body :: line 29 <- main
  < | reach: stmt 22 (line 19): before in body :: line 29 <- main; after in body :: line 29 <- main
  < | reach: stmt 3 (line 8): before in body :: line 29 <- main; after in body :: line 29 <- main
  < | reach: stmt 4 (line 9): before in none; after in none
  < | reach: stmt 5 (line 10): before in none; after in none
  ---
  > | reach: stmt 12 (line 18): before in body :: line 29 <- main, body :: line 30 <- main; after in body :: line 29 <- main, body :: line 30 <- main
  > | reach: stmt 22 (line 19): before in body :: line 29 <- main, body :: line 30 <- main; after in body :: line 29 <- main, body :: line 30 <- main
  > | reach: stmt 3 (line 8): before in body :: line 29 <- main, body :: line 30 <- main; after in body :: line 29 <- main, body :: line 30 <- main
  > | reach: stmt 4 (line 9): before in body :: line 30 <- main; after in body :: line 30 <- main
  > | reach: stmt 5 (line 10): before in body :: line 30 <- main; after in body :: line 30 <- main
  23c25
  < | reach: stmt 8 (line 14): before in body :: line 29 <- main; after in body :: line 29 <- main
  ---
  > | reach: stmt 8 (line 14): before in body :: line 29 <- main, body :: line 30 <- main; after in body :: line 29 <- main, body :: line 30 <- main
  25a28
  > | zones: stmt 1 (line 7) in body :: line 30 <- main: read \nothing; write l
  26a30
  > | zones: stmt 12 (line 18) in body :: line 30 <- main: read x; l; write g
  27a32,33
  > | zones: stmt 3 (line 8) in body :: line 30 <- main: read x; write \nothing
  > | zones: stmt 5 (line 10) in body :: line 30 <- main: read \nothing; write out
  29a36
  > | zones: stmt 8 (line 14) in body :: line 30 <- main: read x; write \nothing
  [1]

An entry produced while the states of body are not saved
(-eva-no-results-function) has no Reach part: its states would not tell
which statements the body reaches. A hit on it behaves as above.

  $ EVA_TEST_CACHE_REACH=replay EVA_TEST_CACHE_REACH_NORESULTS=on frama-c -no-autoload-plugins -load-module eva,test_cache_reach.cmxs -main producer -eva-msg-key cache reach.c > noresults.log 2>&1
  $ grep -E '^(Reach part|hits|reachability)|lookup: hit|answered by the cache' noresults.log
  Reach part of the entry: unknown
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
    and up to 4 more through calls answered by the cache (100% coverage).
  hits on body: 1
  reachability of body unknown: true

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
