The Safety part of a cache entry holds the alarms, the statuses, the
messages of the statuses and the red contexts emitted by its body. A hit
delivers them at its own callstack, and the kernel combines each status with
those emitted before.

  $ dune build -j 8 --cache=disabled --root . test_cache_safety.cmxs

A first analysis from producer analyses body(1, 0) and stores its entry. At
x = 1, the assertion two is invalid and its branch stops; at y = 0, the
division is a sure alarm, with an unknown kernel status and a red context;
ok holds. The statuses of the two assertions come with their messages.
Every write belongs to the body, with no frame above it.

  $ EVA_TEST_CACHE_SAFETY=replay frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -eva-msg-key cache safety.c > replay.log 2>&1
  $ grep -E '^(safety|after the reset|hits on)' replay.log
  safety: red context of property two at safety.c:9 (stmt 3), in the body
  safety: status invalid of two, by Eva, in the body
  safety: message "assertion 'two' got status invalid (stopping propagation)." at safety.c:9, for a status invalid, in the body
  safety: red context of alarm division_by_zero at safety.c:11 (stmt 7), in the body
  safety: alarm division_by_zero at safety.c:11 (stmt 7), status unknown by Eva, in the body
  safety: status valid of ok, by Eva, in the body
  safety: message "assertion 'ok' got status valid." at safety.c:13, for a status valid, in the body
  after the reset: 0 statuses, 0 red contexts
  hits on body: 1

Changing the entry point to main resets the alarms and the statuses of the
first analysis. The second analysis is given the entry. The call
body(2, v & 1) has another key and is analysed; the call body(1, 0) at
line 26 is a hit, and its body is not analysed. Only the clients that the
collector audits are registered, and the hit is admitted.

  $ grep 'call to body' replay.log
    call to body: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: would-store
    call to body: lookup: rejected (entry 1: key-differs); execution: analysed; storage: refused (supplied-only); collector: would-store
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  $ grep -B 1 'lookup: hit' replay.log | sed 's/ *$//'
  [eva:cache] safety.c:26:
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none

Hand-checked results of the second analysis. The first call gives two a
valid status (x = 2) and the division an unknown one (y in {0, 1}); the hit
gives two an invalid status and the division its red context, both for the
callstack of line 26. The kernel joins valid and invalid into unknown. ok
holds at both calls. r1 = 2 + 7 and r2 = 1 + 7.

  $ grep '^| ' replay.log > replay.summary
  $ cat replay.summary
  | end of main: r1 = 9
  | end of main: r2 = 8
  | safety.c:11: red context of alarm division_by_zero in body :: safety.c:26 <- main
  | safety.c:11: status of alarm division_by_zero: unknown
  | safety.c:13: status of ok: valid
  | safety.c:9: red context of two in body :: safety.c:26 <- main
  | safety.c:9: status of two: unknown

The same program with caching disabled gives the same statuses, red
contexts and values.

  $ EVA_TEST_CACHE_SAFETY=reference frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -eva-msg-key cache safety.c > reference.log 2>&1
  $ grep '^| ' reference.log > reference.summary
  $ diff replay.summary reference.summary

In that run, the analysis of the second call consults the history of the
alarms emitted, which holds the division alarm of the first call: the
collector refuses that body as side-table.

  $ grep 'call to body' reference.log
    call to body: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: would-store
    call to body: lookup: no-candidate; execution: analysed; storage: refused (disabled); collector: refused (side-table)

The delivery alone, outside any analysis, after the same reset: the Safety
part is delivered for the callstack of the call at line 26. The alarm is
registered again with its warning, its unknown status and its red context,
and two is invalid. The warning is printed once by the first analysis and
once by the first delivery. A second delivery at the same callstack changes
no status and no red context. The red contexts are then delivered with the
call of body in outer as frame, for a callstack that starts in outer: each
gets a context in body called from outer at line 33.

  $ EVA_TEST_CACHE_SAFETY=deliver frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer safety.c > deliver.log 2>&1
  $ grep -c 'Warning: division by zero' deliver.log
  2
  $ grep -E '^(after the reset|a second delivery|\| )' deliver.log
  after the reset: 0 statuses, 0 red contexts
  a second delivery changes nothing: true
  | safety.c:11: red context of alarm division_by_zero in body :: safety.c:26 <- main
  | safety.c:11: red context of alarm division_by_zero in body :: safety.c:33 <- outer
  | safety.c:11: status of alarm division_by_zero: unknown
  | safety.c:13: status of ok: valid
  | safety.c:9: red context of two in body :: safety.c:26 <- main
  | safety.c:9: red context of two in body :: safety.c:33 <- outer
  | safety.c:9: status of two: invalid

The passes run at the end of the analysis read the states saved at the
statements, and a hit saves none in the body of the called function. The
hit delivers the statements its body reaches, where its callstack answers
the state top (see cache-reach.t): the marking of dead code finds them
reached, and the refinement of the statuses of alarms concludes nothing
there from the states of the analysed calls alone. The statuses delivered
by the hit stay as delivered. The lookup rejects an entry without a Reach
part.

In passes.c, the entry of body(1, 0) comes from an analysis from producer,
and answers the call at line 35 of main; body(2, 1) is analysed. Executed
from main, the second call divides 100 by y = 0 at line 13 when v reads a
non-zero value, and reaches the assertion one when v reads a non-zero value
at line 10. The analysed call alone never divides by zero, and never reaches
one. Reading the states of the analysed call alone, the refinement gave
the division alarm the final status valid, and one was marked unreachable.
The final status below is that of the analysis from producer, where
body(1, 0) is analysed. The record of the functions answered
by a hit is reset with the analysis, here by a change of the entry point.

  $ EVA_TEST_CACHE_SAFETY=replay-out frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -eva-msg-key cache passes.c > passes.log 2>&1
  $ grep -B 1 'lookup: hit' passes.log | sed 's/ *$//'
  [eva:cache] passes.c:35:
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  $ grep -E 'final status|^visits skipped' passes.log
  [eva] passes.c:13: assertion 'Eva,division_by_zero' got final status invalid.
  visits skipped in body: true
  visits skipped in body after the reset: false
  $ grep '^| ' passes.log > passes.summary
  $ cat passes.summary
  | end of main: out = 8
  | passes.c:11: status of one: valid
  | passes.c:13: red context of alarm division_by_zero in body :: passes.c:35 <- main
  | passes.c:13: status of alarm division_by_zero: unknown
  | passes.c:8: status of post: valid
  | passes.c:9-16: status of behavior default! in function body: valid
  $ EVA_TEST_CACHE_SAFETY=reference-out frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs passes.c > passes-reference.log 2>&1
  $ grep '^| ' passes-reference.log > passes-reference.summary
  $ diff passes.summary passes-reference.summary

The same entry supplied by hand without its Reach part (PART=drop) is
rejected (missing-points), body is analysed, and the statuses are those of
caching disabled.

  $ EVA_TEST_CACHE_SAFETY=replay-out EVA_TEST_CACHE_SAFETY_PART=drop frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -eva-msg-key cache passes.c > passes-drop.log 2>&1
  $ grep -B 1 'missing-points' passes-drop.log | sed 's/ *$//'
  [eva:cache] passes.c:35:
    call to body: lookup: rejected (entry 1: missing-points); execution: analysed; storage: refused (supplied-only); collector: would-store
  $ grep '^| ' passes-drop.log > passes-drop.summary
  $ diff passes-drop.summary passes-reference.summary

The summary of the analysis counts the statements reached by the analysed
call and by the hit: 14, as with caching disabled. The loop at line 14,
which no call reaches, is not counted. The first line is that of the
analysis from producer. The same count follows the rejection of the entry
without a Reach part.

  $ grep 'statements reached' passes.log
    In these functions, 11 statements reached (out of 12): 92% coverage.
    In these functions, 14 statements reached (out of 15): 93% coverage.
  $ grep 'statements reached' passes-reference.log
    In these functions, 14 statements reached (out of 15): 93% coverage.
  $ grep 'statements reached (out of 15)' passes-drop.log
    In these functions, 14 statements reached (out of 15): 93% coverage.

In the reverse order, body(1, 0) is analysed, and the entry of body(2, 1),
produced from producer_safe, answers the call at line 44. Reading the
states of the analysed call alone, where y = 0, the refinement made the
alarm invalid; with caching disabled it is unknown.

  $ EVA_TEST_CACHE_SAFETY=replay-out EVA_TEST_CACHE_SAFETY_MAIN=reverse frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer_safe -eva-msg-key cache passes.c > reverse.log 2>&1
  $ grep -B 1 'lookup: hit' reverse.log | sed 's/ *$//'
  [eva:cache] passes.c:44:
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  $ grep '^| ' reverse.log > reverse.summary
  $ EVA_TEST_CACHE_SAFETY=reference-out frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main reverse passes.c > reverse-reference.log 2>&1
  $ grep '^| ' reverse-reference.log > reverse-reference.summary
  $ diff reverse.summary reverse-reference.summary

From no_return, body(1, 0) is a hit and body(3, 1) never returns: no
analysed call reaches the return statement of body. Its postcondition is
not marked unreachable.

  $ EVA_TEST_CACHE_SAFETY=replay-out EVA_TEST_CACHE_SAFETY_MAIN=no_return frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -eva-msg-key cache passes.c > no-return.log 2>&1
  $ grep -B 1 'lookup: hit' no-return.log | sed 's/ *$//'
  [eva:cache] passes.c:51:
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  $ grep '^| ' no-return.log > no-return.summary
  $ EVA_TEST_CACHE_SAFETY=reference-out frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main no_return passes.c > no-return-reference.log 2>&1
  $ grep '^| ' no-return-reference.log > no-return-reference.summary
  $ diff no-return.summary no-return-reference.summary

Eva.Export generates assertions from the states saved at the statements of
a function, and gives them a valid status. In body, it asserts \false at
line 14, which no call reaches, and nothing at the statements that the hit
reaches, where its callstack answers top.

  $ EVA_TEST_CACHE_SAFETY=replay-out EVA_TEST_CACHE_SAFETY_EXPORT=on frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer passes.c > export.log 2>&1
  $ grep 'export' export.log
  exported at passes.c:14: assert Eva_export: \false;
  annotations exported in body: 1
  | <generated by Frama-C kernel>: status of Eva_export: valid

With caching disabled, Export asserts \false at line 14 as well, and the
values at the statements of body.

  $ EVA_TEST_CACHE_SAFETY=reference-out EVA_TEST_CACHE_SAFETY_EXPORT=on frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs passes.c > export-reference.log 2>&1
  $ grep 'export' export-reference.log
  exported at passes.c:10: assert Eva_export: -2147483648 ≤ v ≤ 2147483647;
  exported at passes.c:13: assert Eva_export: -2147483648 ≤ v ≤ 2147483647;
  exported at passes.c:13: assert Eva_export: 0 ≤ y ≤ 1;
  exported at passes.c:14: assert Eva_export: 1 ≤ x ≤ 2;
  exported at passes.c:14: assert Eva_export: \false;
  exported at passes.c:15: assert Eva_export: g ≡ 7;
  exported at passes.c:15: assert Eva_export: 1 ≤ x ≤ 2;
  annotations exported in body: 7
  | <generated by Frama-C kernel>: status of Eva_export: valid
  | passes.c:10: status of Eva_export: valid
  | passes.c:13: status of Eva_export: valid
  | passes.c:14: status of Eva_export: valid
  | passes.c:15: status of Eva_export: valid

With the entry without a Reach part, rejected, body is analysed, and Export
generates the same annotations as with caching disabled.

  $ EVA_TEST_CACHE_SAFETY=replay-out EVA_TEST_CACHE_SAFETY_EXPORT=on EVA_TEST_CACHE_SAFETY_PART=drop frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer passes.c > export-drop.log 2>&1
  $ grep 'export' export-drop.log > export-drop.lines
  $ grep 'export' export-reference.log > export-reference.lines
  $ diff export-drop.lines export-reference.lines

Other plug-ins read the states saved at the statements after the analysis:
Nonterm reports a statement without a state as unreachable, and Metrics
counts it as unreached. When one of them is loaded, every supplied
candidate is rejected for consumer, and the body is analysed.

  $ EVA_TEST_CACHE_SAFETY=replay-out frama-c -no-autoload-plugins -load-module eva,nonterm,test_cache_safety.cmxs -main producer -eva-msg-key cache passes.c > nonterm.log 2>&1
  $ grep -E 'call to body|^hits on' nonterm.log
    call to body: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: would-store
    call to body: lookup: rejected (entry 1: consumer); execution: analysed; storage: refused (supplied-only); collector: would-store
    call to body: lookup: rejected (entry 1: consumer); execution: analysed; storage: refused (supplied-only); collector: would-store
  hits on body: 0

Metrics loads the server, whose hook on the changes of annotations refuses
with callback a body that registers an alarm. The entry is that of
body(2, 1), which registers none, and the first call of main is the
candidate. The second call, body(1, 0), registers the division alarm.

  $ EVA_TEST_CACHE_SAFETY=replay-out frama-c -no-autoload-plugins -load-module eva,metrics,test_cache_safety.cmxs -main producer_safe -eva-msg-key cache passes.c > metrics.log 2>&1
  $ grep -E 'call to body|^hits on' metrics.log
    call to body: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: would-store
    call to body: lookup: rejected (entry 1: consumer); execution: analysed; storage: refused (supplied-only); collector: would-store
    call to body: lookup: rejected (entry 1: consumer); execution: analysed; storage: refused (supplied-only); collector: refused (callback)
  hits on body: 0

A hit records the called function alone among those whose statements have
no state. Supply refuses an entry for a body that may call a function that
has a body, before any lookup; the lookup rejects the entries of the other
bodies with a call, produced entries included, with nested-delivery (see
nested-access.t).

  $ EVA_TEST_CACHE_SAFETY=nested frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs safety.c > nested.log 2>&1
  $ grep '^refused' nested.log
  refused: Supplied_entries.supply: the body of outer may call a function that has a body

The Safety part of a body with a call is incomplete. When child is analysed
in the analysis of parent, its writes are recorded in its own part, and the
part of parent has none of them. When a hit answers the call of child, the
writes it delivers are recorded in the part of parent, with the call of
child as frame. Since the lookup rejects the entry of parent, no hit
delivers this part.

  $ EVA_TEST_CACHE_SAFETY=enclosing frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -eva-cache-collect -eva-msg-key cache enclosing.c > enclosing.log 2>&1
  $ grep -E '^(Safety part of parent|second analysis|hits on)|call to (child|parent):' enclosing.log
    call to child: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: would-store
  Safety part of parent: none
    call to parent: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: would-store
  second analysis
    call to child: lookup: hit (entry 1); execution: not-analysed; storage: none
  Safety part of parent: red context of property big at enclosing.c:7 (stmt 1), in child :: enclosing.c:12 (stmt 5)
  Safety part of parent: status invalid of big, by Eva, in child :: enclosing.c:12 (stmt 5)
  Safety part of parent: message "check 'big' got status invalid." at enclosing.c:7, for a status invalid, in child :: enclosing.c:12 (stmt 5)
    call to parent: lookup: no-candidate; execution: analysed; storage: refused (supplied-only); collector: would-store
  hits on child: 1

A recording belongs to the project current when it starts. A client of the
statement hooks, registered as classified so that the collector admits it,
enters a second project with Project.on the first time it runs in body,
during the analysis from producer, and sets a red status there. Each
recording in progress, of body and of producer, is refused for
project-switch, and no entry is stored. The analysis from main has no
candidate, and its tables are those of the run with caching disabled and
the same client.

  $ EVA_TEST_CACHE_SAFETY=crossing frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -eva-msg-key cache safety.c > crossing.log 2>&1
  $ grep -E 'call to|entries produced|collector-refused' crossing.log
    call to body: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: refused (project-switch)
    call to producer: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: refused (project-switch)
  collector-refused-project-switch of body: 1
  collector-refused-project-switch of producer: 1
  entries produced for body: 0
    call to body: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: would-store
    call to body: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: refused (side-table)
    call to main: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: refused (sweep)
  $ grep '^| ' crossing.log > crossing.summary
  $ EVA_TEST_CACHE_SAFETY=crossing-reference frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -eva-msg-key cache safety.c > crossing-reference.log 2>&1
  $ grep '^| ' crossing-reference.log > crossing-reference.summary
  $ diff crossing.summary crossing-reference.summary

The kernel runs no hook of the change of project for a change made during
such a hook, but it counts every change. Here the analysis from producer
runs in a hook of the change to a copy of the project. The first time it
runs in body, the client of the statement hooks enters the first project
with Project.on and leaves it, without writing there. Each recording in
progress is refused for
project-switch, and no entry is stored. The analysis from main, in the copy,
has no candidate. The tables of the copy, and those of the first project,
where Eva wrote nothing, are those of the run with caching disabled in the
same setting.

  $ EVA_TEST_CACHE_SAFETY=reentrant frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -eva-msg-key cache safety.c > reentrant.log 2>&1
  $ grep -E 'entered|call to|entries produced|collector-refused' reentrant.log
  entered the first project: true
    call to body: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: refused (project-switch)
    call to producer: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: refused (project-switch)
  collector-refused-project-switch of body: 1
  collector-refused-project-switch of producer: 1
  entries produced for body: 0
    call to body: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: would-store
    call to body: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: refused (side-table)
    call to main: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: refused (sweep)
  $ grep '^| first' reentrant.log
  | first project: 0 statuses, 0 red contexts
  $ grep '^| ' reentrant.log > reentrant.summary
  $ EVA_TEST_CACHE_SAFETY=reentrant-reference frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -eva-msg-key cache safety.c > reentrant-reference.log 2>&1
  $ grep '^| ' reentrant-reference.log > reentrant-reference.summary
  $ diff reentrant.summary reentrant-reference.summary

The alarms of an entry are those of the options of the analysis that
produced it. An entry used by another analysis must come from an analysis
with the same options that decide which alarms and statuses are emitted;
nothing checks it yet. This run breaks that premise on purpose, to show the
current behaviour: the entry of body is produced with
-no-warn-signed-overflow and used with -warn-signed-overflow. The hit hides
the overflow alarm that the analysis of body emits with caching disabled.
Both analyses run with the category signed-overflow inactive: with the
category active, the assumption of 2's complement is a message printed once,
and the collector refuses the body (side-table).

  $ EVA_TEST_CACHE_SAFETY=replay-out EVA_TEST_CACHE_SAFETY_OVERFLOW=on frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -no-warn-signed-overflow -eva-warn-key signed-overflow=inactive -eva-msg-key cache overflow.c > overflow.log 2>&1
  $ grep -B 1 'lookup: hit' overflow.log | sed 's/ *$//'
  [eva:cache] overflow.c:19:
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  $ grep '^| ' overflow.log > overflow.summary
  $ EVA_TEST_CACHE_SAFETY=reference-out frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -eva-warn-key signed-overflow=inactive overflow.c > overflow-reference.log 2>&1
  $ grep '^| ' overflow-reference.log > overflow-reference.summary
  $ diff overflow.summary overflow-reference.summary
  1a2,3
  > | overflow.c:8: red context of alarm signed_overflow in body :: overflow.c:19 <- main
  > | overflow.c:8: status of alarm signed_overflow: invalid
  [1]

The actions of the message and warning categories decide the end state, not
only the messages: a hit prints the messages of the statuses and the alarms
of its entry, but not others, such as the assumption of 2's complement for
an overflow. The lookup compares the status of every warning category of
the kernel and of Eva with its status when the analysis of the body that
produced the entry started, and rejects the entry when one differs
(warn-categories). The entry of body is produced with the category
signed-overflow inactive, and looked up with the category set to abort: body
is analysed, and the analysis stops at the overflow, as with caching
disabled.

  $ EVA_TEST_CACHE_SAFETY=replay-out EVA_TEST_CACHE_SAFETY_CATEGORY=signed-overflow=abort frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -no-warn-signed-overflow -eva-warn-key signed-overflow=inactive -eva-msg-key cache overflow.c > fatal.log 2>&1
  $ sed -n '/^second analysis/,$p' fatal.log > fatal.second
  $ grep -E "call to body|2's complement|^analysis aborted" fatal.second
  [eva:signed-overflow] overflow.c:8: Failure: 2's complement assumed for overflow
    call to body: lookup: rejected (entry 1: warn-categories); execution: interrupted; storage: none
  analysis aborted
  $ grep '^| ' fatal.log > fatal.summary
  $ EVA_TEST_CACHE_SAFETY=reference-out EVA_TEST_CACHE_SAFETY_CATEGORY=signed-overflow=abort frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -no-warn-signed-overflow -eva-msg-key cache overflow.c > fatal-reference.log 2>&1
  $ grep -E "2's complement|^analysis aborted" fatal-reference.log
  [eva:signed-overflow] overflow.c:8: Failure: 2's complement assumed for overflow
  analysis aborted
  $ grep '^| ' fatal-reference.log > fatal-reference.summary
  $ diff fatal.summary fatal-reference.summary

The same within one analysis. In same.c, the first call of body is analysed
with the category inactive, and its entry is stored. At the end of the
analysis of other, an observer of the Safety part supplies that entry and
sets the category to abort; nothing else in Eva sees the change, and no hit
runs such an observer. The second call of body rejects the entry and stops
at the overflow, as with caching disabled.

  $ EVA_TEST_CACHE_SAFETY=same EVA_TEST_CACHE_SAFETY_SUPPLY=on EVA_TEST_CACHE_SAFETY_TRIGGER=observer frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -no-warn-signed-overflow -eva-warn-key signed-overflow=inactive -eva-msg-key cache same.c > same.log 2>&1
  $ grep -E "call to body|^supplied|2's complement|^analysis aborted|^hits on" same.log
    call to body: lookup: rejected (entry 1: key-differs); execution: analysed; storage: refused (supplied-only); collector: would-store
  supplied during the analysis: 1
  [eva:signed-overflow] same.c:8: Failure: 2's complement assumed for overflow
    call to body: lookup: rejected (entry 1: key-differs), rejected (entry 2: warn-categories); execution: interrupted; storage: none
  analysis aborted
  hits on body: 0
  $ grep '^| ' same.log > same.summary
  $ EVA_TEST_CACHE_SAFETY=same EVA_TEST_CACHE_SAFETY_TRIGGER=observer frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -no-warn-signed-overflow -eva-warn-key signed-overflow=inactive -eva-msg-key cache same.c > same-reference.log 2>&1
  $ grep '^| ' same-reference.log > same-reference.summary
  $ diff same.summary same-reference.summary

An entry rejected for warn-categories does not end the lookup: the next
candidate is examined. In next.c, body has no alarm. The observer supplies
the entry stored for the first call of body, then a copy of it written by
hand, which carries no status of the warning categories. The second call of
body rejects the hand-written entry for x = 5 (key-differs) and the stored
one (warn-categories), and the copy answers it. The tables are those of the
run with caching disabled.

  $ EVA_TEST_CACHE_SAFETY=same EVA_TEST_CACHE_SAFETY_SUPPLY=on EVA_TEST_CACHE_SAFETY_TRIGGER=observer EVA_TEST_CACHE_SAFETY_NEXT=1 frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -no-warn-signed-overflow -eva-warn-key signed-overflow=inactive -eva-msg-key cache next.c > next.log 2>&1
  $ grep -A 1 'entry 2: warn-categories' next.log | sed 's/ *$//'
    call to body: lookup: rejected (entry 1: key-differs), rejected (entry 2: warn-categories),
    hit (entry 3); execution: not-analysed; storage: none
  $ grep '^| ' next.log > next.summary
  $ EVA_TEST_CACHE_SAFETY=same EVA_TEST_CACHE_SAFETY_TRIGGER=observer frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -no-warn-signed-overflow -eva-warn-key signed-overflow=inactive -eva-msg-key cache next.c > next-reference.log 2>&1
  $ grep '^| ' next-reference.log > next-reference.summary
  $ diff next.summary next-reference.summary

A hit skips the analysis of the body, and with it the calls that this
analysis makes to the clients of Eva and of the kernel; the delivery of the
Safety part calls some of them again. A client may count its calls, change
a setting, or add statuses of its own, and the collector cannot tell what
it does. A hit is admitted only when no client that the collector does not
audit is registered on a hook that the analysis of the body or the hit
would run: the hooks on calls and on statements of Eva, the hooks of red
statuses, the hooks on the addition and the status of properties, the hooks
on the changes of annotations, the listeners of the logger, for all
plug-ins (listener) or for one (register), the observers of its history,
the hooks on messages, the observers of Hook.Opaque, of the reads of the
metadata of allocated blocks, of the updates of their validity and of the
history of origins, the daemons of Async, the hooks on the changes of the
current location, the hooks on the statistics of performance by
callstack, and the observers of the Safety part, of the Reach part and of
the result of the collector of each analysed body. Otherwise, every supplied
candidate is rejected for callback, and the body is analysed. Below, one
client of each hook is registered after the analysis from producer of
safety.c; both calls of body in the analysis from main reject the entry.

  $ for c in call call-results statement red status property annotations listener register history messages opaque metadata validity origin daemon location perf safety-result reach-result collector-result; do EVA_TEST_CACHE_SAFETY=replay EVA_TEST_CACHE_SAFETY_CLIENT=$c frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -eva-msg-key cache safety.c > client-$c.log 2>&1; echo "$c: exit $?"; done
  call: exit 0
  call-results: exit 0
  statement: exit 0
  red: exit 0
  status: exit 0
  property: exit 0
  annotations: exit 0
  listener: exit 0
  register: exit 0
  history: exit 0
  messages: exit 0
  opaque: exit 0
  metadata: exit 0
  validity: exit 0
  origin: exit 0
  daemon: exit 0
  location: exit 0
  perf: exit 0
  safety-result: exit 0
  reach-result: exit 0
  collector-result: exit 0
  $ for c in call call-results statement red status property annotations listener register history messages opaque metadata validity origin daemon location perf safety-result reach-result collector-result; do grep '^client' client-$c.log; done
  client call: hits on body: 0, rejected for callback: 2
  client call-results: hits on body: 0, rejected for callback: 2
  client statement: hits on body: 0, rejected for callback: 2
  client red: hits on body: 0, rejected for callback: 2
  client status: hits on body: 0, rejected for callback: 2
  client property: hits on body: 0, rejected for callback: 2
  client annotations: hits on body: 0, rejected for callback: 2
  client listener: hits on body: 0, rejected for callback: 2
  client register: hits on body: 0, rejected for callback: 2
  client history: hits on body: 0, rejected for callback: 2
  client messages: hits on body: 0, rejected for callback: 2
  client opaque: hits on body: 0, rejected for callback: 2
  client metadata: hits on body: 0, rejected for callback: 2
  client validity: hits on body: 0, rejected for callback: 2
  client origin: hits on body: 0, rejected for callback: 2
  client daemon: hits on body: 0, rejected for callback: 2
  client location: hits on body: 0, rejected for callback: 2
  client perf: hits on body: 0, rejected for callback: 2
  client safety-result: hits on body: 0, rejected for callback: 2
  client reach-result: hits on body: 0, rejected for callback: 2
  client collector-result: hits on body: 0, rejected for callback: 2

The observers of the kernel through which the collector of block accesses
sees what happens during the analysis of a body are registered as audited
by the collector, and by no other client of the tree. One of them runs at a
hit with an audited client: the client of the server on the changes of
annotations is audited for the lookup, and runs through Hook.Opaque.wrap,
which runs the observers of Hook.Opaque. In alone.c, the hit on body
registers an alarm that the analysis from main has not registered before;
the server is loaded after the analysis from producer. An observer of
Hook.Opaque registered without an audit makes the call reject the entry with
callback, and is not called during a delivery; registered as audited, the
call hits, and the observer is called during the delivery.

  $ for c in opaque opaque-audited; do EVA_TEST_CACHE_SAFETY=replay EVA_TEST_CACHE_SAFETY_SERVER=late EVA_TEST_CACHE_SAFETY_CLIENT=$c frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -eva-msg-key cache alone.c > server-$c.log 2>&1; echo "$c: exit $?"; done
  opaque: exit 0
  opaque-audited: exit 0
  $ grep -hE '^(client|observer)' server-opaque.log server-opaque-audited.log
  client opaque: hits on body: 0, rejected for callback: 1
  observer calls during a delivery: 0
  client opaque-audited: hits on body: 1, rejected for callback: 0
  observer calls during a delivery: 1

The precondition of pre in metadata.c reads the validity of an allocated
block. At a hit, the check of the preconditions runs the observer of the
reads of the metadata of allocated blocks, through the observer of the
collector, which records the body of main and runs the observer that it
replaced. An observer registered without an audit makes both calls reject
the hand-written entry with callback; registered as audited, the second
call hits, and the observer is called during the check of the
preconditions of that hit.

  $ for c in metadata metadata-audited; do EVA_TEST_CACHE_SAFETY=precondition EVA_TEST_CACHE_SAFETY_CLIENT=$c frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -eva-alloc-returns-null -eva-msg-key cache metadata.c > precondition-$c.log 2>&1; echo "$c: exit $?"; done
  metadata: exit 0
  metadata-audited: exit 0
  $ grep -hE '^(client|observer)' precondition-metadata.log precondition-metadata-audited.log
  client metadata: hits on pre: 0, rejected for callback: 2
  observer calls during a delivery: 0
  client metadata-audited: hits on pre: 1, rejected for callback: 0
  observer calls during a delivery: 1

The audited observers of the metadata are known by their physical identity,
in a registry that holds them weakly. 128 audited observers of 64 KiB each,
installed and removed in turn, are collected. An audited observer installed
again without the flag does not count as a client that is not audited;
another observer installed without the flag counts, and counts once removed.

  $ EVA_TEST_CACHE_SAFETY=registry frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs safety.c > registry.log 2>&1
  $ grep -E '^(audited|after)' registry.log
  audited observers removed and still alive: 0 of 128
  after them, an observer that is not audited: false
  after an audited observer installed again without the flag: false
  after another observer installed without the flag: true
  after its removal: true

The server plug-in registers a client of the hooks on the changes of
annotations when it loads. With it, the registration of the alarm of body
runs that client, and the collector refuses the body for callback: no entry
is stored, and the analysis from main has no candidate.

  $ EVA_TEST_CACHE_SAFETY=replay frama-c -no-autoload-plugins -load-module eva,server,test_cache_safety.cmxs -main producer -eva-msg-key cache safety.c > server.log 2>&1
  $ grep 'call to body' server.log
    call to body: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: refused (callback)
    call to body: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: refused (callback)
    call to body: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: refused (side-table)

A client can change a setting during a hit, after the lookup. The entry is
produced with the category inactive; in the analysis that uses it, a client
of the hook on calls sets the category to abort at the call of body. The
entry is rejected for callback, and the analysis stops at the overflow, as
with caching disabled. The hit printed nothing and gave out = 8 before a
comparison of the categories after the delivery was added; that comparison
no longer exists.

  $ EVA_TEST_CACHE_SAFETY=replay-out EVA_TEST_CACHE_SAFETY_HOOK=signed-overflow=abort frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -no-warn-signed-overflow -eva-warn-key signed-overflow=inactive -eva-msg-key cache overflow.c > hook.log 2>&1
  $ sed -n '/^second analysis/,$p' hook.log > hook.second
  $ grep -E "call to body|2's complement|^analysis aborted" hook.second
  [eva:signed-overflow] overflow.c:8: Failure: 2's complement assumed for overflow
    call to body: lookup: rejected (entry 1: callback); execution: interrupted; storage: none
  analysis aborted
  $ grep '^| ' hook.log > hook.summary
  $ EVA_TEST_CACHE_SAFETY=reference-out EVA_TEST_CACHE_SAFETY_HOOK=signed-overflow=abort frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -no-warn-signed-overflow -eva-warn-key signed-overflow=inactive -eva-msg-key cache overflow.c > hook-reference.log 2>&1
  $ grep -E "2's complement|^analysis aborted" hook-reference.log
  [eva:signed-overflow] overflow.c:8: Failure: 2's complement assumed for overflow
  analysis aborted
  $ grep '^| ' hook-reference.log > hook-reference.summary
  $ diff hook.summary hook-reference.summary

The change can also be undone before the hit ends. In inside.c, the check
trigger of other makes a client supply the entries stored so far and
register two more: one of the hook on calls sets signed-overflow to abort at
the next call of body, one of the hooks of red statuses sets it back to
inactive at each red status. With caching disabled, the second call of body
stops at the overflow, before the red status of later. With caching, both
calls of body reject the entries for callback, and the analysis stops at the
same point. When red clients were admitted, the entry of the first call
answered the second: the red status of later restored the category before
the comparison after the delivery, and the hit gave out = 8.

  $ EVA_TEST_CACHE_SAFETY=same EVA_TEST_CACHE_SAFETY_SUPPLY=on EVA_TEST_CACHE_SAFETY_TRIGGER=red EVA_TEST_CACHE_SAFETY_HOOK=signed-overflow=abort EVA_TEST_CACHE_SAFETY_UNDO=1 frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -no-warn-signed-overflow -eva-warn-key signed-overflow=inactive -eva-msg-key cache inside.c > inside.log 2>&1
  $ grep -E "call to body|2's complement|^analysis aborted|^hits on" inside.log
    call to body: lookup: rejected (entry 1: callback); execution: analysed; storage: refused (supplied-only); collector: refused (callback)
  [eva:signed-overflow] inside.c:9: Failure: 2's complement assumed for overflow
    call to body: lookup: rejected (entry 1: callback); execution: interrupted; storage: none
  analysis aborted
  hits on body: 0
  $ grep '^| ' inside.log > inside.summary
  $ EVA_TEST_CACHE_SAFETY=same EVA_TEST_CACHE_SAFETY_TRIGGER=red EVA_TEST_CACHE_SAFETY_HOOK=signed-overflow=abort EVA_TEST_CACHE_SAFETY_UNDO=1 frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -no-warn-signed-overflow -eva-warn-key signed-overflow=inactive -eva-msg-key cache inside.c > inside-reference.log 2>&1
  $ grep '^| ' inside-reference.log > inside-reference.summary
  $ diff inside.summary inside-reference.summary

A hit stopped after its delivery has published its whole Safety part,
which the analysis of the body does not. In interleave.c, the client of the
hook on calls sets signed-overflow to abort at the call of body, and a
client of the hooks of red statuses counts its calls. With caching
disabled, the analysis of body sets the red status of first, calls the
client once, and stops at the overflow, before last. The entry is rejected
for callback, with the same result. When red clients were admitted, the
hit called the client three times and set the red status of last before
the comparison stopped the analysis.

  $ EVA_TEST_CACHE_SAFETY=replay-out EVA_TEST_CACHE_SAFETY_HOOK=signed-overflow=abort EVA_TEST_CACHE_SAFETY_COUNT=red frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -no-warn-signed-overflow -eva-warn-key signed-overflow=inactive -eva-slevel 10 -eva-msg-key cache interleave.c > interleave.log 2>&1
  $ sed -n '/^second analysis/,$p' interleave.log > interleave.second
  $ grep -E "call to body|^analysis aborted|^red hook calls" interleave.second
    call to body: lookup: rejected (entry 1: callback); execution: interrupted; storage: none
  analysis aborted
  red hook calls: 1
  $ grep '^| ' interleave.log > interleave.summary
  $ EVA_TEST_CACHE_SAFETY=reference-out EVA_TEST_CACHE_SAFETY_HOOK=signed-overflow=abort EVA_TEST_CACHE_SAFETY_COUNT=red frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -no-warn-signed-overflow -eva-warn-key signed-overflow=inactive -eva-slevel 10 -eva-msg-key cache interleave.c > interleave-reference.log 2>&1
  $ grep -E "^analysis aborted|^red hook calls" interleave-reference.log
  analysis aborted
  red hook calls: 1
  $ grep '^| ' interleave-reference.log > interleave-reference.summary
  $ diff interleave.summary interleave-reference.summary

A hit can also be stopped where the analysis of the body is not. In
pre-route.c, a client of the hooks on statuses sets signed-overflow to
abort when the precondition of pre is evaluated at line 18, where a
hand-written entry is a candidate. pre has no overflow: with caching
disabled, the analysis ends with out = 5. The entry is rejected for
callback, with the same result. When the hit was admitted, the comparison
after the delivery stopped the analysis.

  $ EVA_TEST_CACHE_SAFETY=precondition EVA_TEST_CACHE_SAFETY_ROUTE=pre frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -eva-warn-key signed-overflow=inactive -eva-msg-key cache pre-route.c > pre-route.log 2>&1
  $ grep -E "call to pre|^analysis aborted|^hits on" pre-route.log
    call to pre: lookup: rejected (entry 1: callback); execution: analysed; storage: refused (supplied-only); collector: refused (callback)
    call to pre: lookup: rejected (entry 1: callback); execution: analysed; storage: refused (supplied-only); collector: refused (callback)
  hits on pre: 0
  $ grep '^| ' pre-route.log > pre-route.summary
  $ grep '^| end' pre-route.summary
  | end of main: out = 5
  $ EVA_TEST_CACHE_SAFETY=precondition-reference EVA_TEST_CACHE_SAFETY_ROUTE=pre frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -eva-warn-key signed-overflow=inactive -eva-msg-key cache pre-route.c > pre-route-reference.log 2>&1
  $ grep '^| ' pre-route-reference.log > pre-route-reference.summary
  $ diff pre-route.summary pre-route-reference.summary

The same with a listener of the logger. In later.c, the listener sets
signed-overflow to abort when it reads the line that reports a hit on body.
With caching disabled, no hit is reported, and the analysis ends with
out = 8. The entry is rejected for callback, with the same result. When the
hit was admitted, the comparison after the delivery stopped the analysis.

  $ EVA_TEST_CACHE_SAFETY=replay-out EVA_TEST_CACHE_SAFETY_ROUTE=log frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -no-warn-signed-overflow -eva-warn-key signed-overflow=inactive -eva-msg-key cache later.c > later.log 2>&1
  $ sed -n '/^second analysis/,$p' later.log > later.second
  $ grep -E "call to body|^analysis aborted|^hits on" later.second
    call to body: lookup: rejected (entry 1: callback); execution: analysed; storage: refused (supplied-only); collector: would-store
  hits on body: 0
  $ grep '^| ' later.log > later.summary
  $ EVA_TEST_CACHE_SAFETY=reference-out EVA_TEST_CACHE_SAFETY_ROUTE=log frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -no-warn-signed-overflow -eva-warn-key signed-overflow=inactive -eva-msg-key cache later.c > later-reference.log 2>&1
  $ grep '^| ' later-reference.log > later-reference.summary
  $ diff later.summary later-reference.summary

A client of the hooks of red statuses can add a red status of its own. In
repeat.c, the check never of body fails at the three iterations of its
loop. Registered after the analysis from producer, the client adds a red
status of never at no statement each time the hook runs for another red
status; the hook runs again for the status that the client adds. The entry
is rejected for callback: the hook is called 6 times, and a global red
context of never is set, as with caching disabled. When red clients were
admitted, the hit called the hook 12 times.

  $ EVA_TEST_CACHE_SAFETY=replay-out EVA_TEST_CACHE_SAFETY_OWNRED=1 frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -eva-slevel 10 -eva-msg-key cache repeat.c > own-red.log 2>&1
  $ sed -n '/^second analysis/,$p' own-red.log > own-red.second
  $ grep -E "call to body|^red hook calls" own-red.second
    call to body: lookup: rejected (entry 1: callback); execution: analysed; storage: refused (supplied-only); collector: refused (callback)
  red hook calls: 6
  $ grep '^| ' own-red.log > own-red.summary
  $ cat own-red.summary
  | end of main: out = 8
  | global: red context of never in body :: repeat.c:20 <- main
  | repeat.c:8: red context of never in body :: repeat.c:20 <- main
  | repeat.c:8: status of never: invalid
  $ EVA_TEST_CACHE_SAFETY=reference-out EVA_TEST_CACHE_SAFETY_OWNRED=1 frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -eva-slevel 10 -eva-msg-key cache repeat.c > own-red-reference.log 2>&1
  $ grep '^red hook calls' own-red-reference.log
  red hook calls: 6
  $ grep '^| ' own-red-reference.log > own-red-reference.summary
  $ diff own-red.summary own-red-reference.summary

The same client, registered before any analysis, adds its red status only
in the analysis from producer. The collector refuses the body for callback
when the client runs during its analysis, and no entry is stored: the
analysis from main has no candidate, and its tables are those of the run
with caching disabled and no client. When red clients were admitted, the
entry was stored, and the hit set the global red context of never in the
analysis from main.

  $ EVA_TEST_CACHE_SAFETY=replay-out EVA_TEST_CACHE_SAFETY_OWNRED=producer frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -eva-slevel 10 -eva-msg-key cache repeat.c > own-producer.log 2>&1
  $ grep -E "call to body|^no entry" own-producer.log
    call to body: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: refused (callback)
  no entry produced for body
    call to body: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: refused (callback)
  $ grep '^| ' own-producer.log > own-producer.summary
  $ EVA_TEST_CACHE_SAFETY=reference-out frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -eva-slevel 10 -eva-msg-key cache repeat.c > own-producer-reference.log 2>&1
  $ grep '^| ' own-producer-reference.log > own-producer-reference.summary
  $ diff own-producer.summary own-producer-reference.summary

Printing the message of a status reads the history of the logger, and a
hit makes the same read when it prints the message again: a body whose
statuses come with messages would store. With the category alarm printed
once, the policy of the category refuses the body.

  $ frama-c -no-autoload-plugins -load-module eva -eva -main producer -eva-cache-collect -eva-msg-key cache safety.c > status-message.log 2>&1
  $ grep 'call to body' status-message.log
    call to body: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: would-store
  $ frama-c -no-autoload-plugins -load-module eva -eva -main producer -eva-cache-collect -eva-msg-key cache -eva-warn-key alarm=once safety.c > status-once.log 2>&1
  $ grep 'call to body' status-once.log
    call to body: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: refused (side-table)

The message of a status is part of the Safety part. A hit prints it again
through the function that the body uses, at its position, with the
callstack of the hit: the action of the category applies, and a text
printed before at the same position is not printed again. The first
analysis runs with the category alarm inactive, and prints no message of
that category. With the category set to abort, the analysis with caching
disabled stops at the invalid assertion two, in the call at line 25, and so
does the hit.

  $ EVA_TEST_CACHE_SAFETY=replay-out EVA_TEST_CACHE_SAFETY_ALARM=abort frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -eva-warn-key alarm=inactive -eva-msg-key cache message.c > abort.log 2>&1
  $ grep -E 'lookup: hit|Failure|fatal|aborted' abort.log | sed 's/ *$//'
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  [eva:alarm] message.c:9: Failure:
  [eva] User Error: warning alarm treated as fatal error.
  analysis aborted
  $ grep '^| ' abort.log > abort.summary
  $ EVA_TEST_CACHE_SAFETY=reference-out EVA_TEST_CACHE_SAFETY_ALARM=abort frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs message.c > abort-reference.log 2>&1
  $ grep -E 'Failure|fatal|aborted' abort-reference.log | sed 's/ *$//'
  [eva:alarm] message.c:9: Failure:
  [eva] User Error: warning alarm treated as fatal error.
  analysis aborted
  $ grep '^| ' abort-reference.log > abort-reference.summary
  $ diff abort.summary abort-reference.summary

With the message category callstacks, the messages of the statuses printed
at the hit end with the callstack of the call at line 25, as with caching
disabled. Below are the messages of the statuses in the analysis from main.

  $ EVA_TEST_CACHE_SAFETY=replay-out EVA_TEST_CACHE_SAFETY_ALARM=active frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -eva-warn-key alarm=inactive -eva-msg-key callstacks,progress message.c > stacks.log 2>&1
  $ sed -n '/^second analysis/,$p' stacks.log > stacks.second
  $ awk '/^\[/ { p = /^\[eva:(alarm|progress)\] message\.c:[0-9]+:/ && !/Reusing/ } p' stacks.second > stacks.messages
  $ sed 's/ *$//' stacks.messages
  [eva:progress] message.c:9: assertion 'two' got status valid.
  [eva:progress] message.c:6:
    function body: postcondition 'post' got status valid.
    stack: body :: message.c:23 <- main
  [eva:alarm] message.c:9: Warning:
    assertion 'two' got status invalid (stopping propagation).
  [eva:progress] message.c:6:
    function body: postcondition 'post' got status valid.
    stack: body :: message.c:25 <- main
  $ EVA_TEST_CACHE_SAFETY=reference-out frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -eva-msg-key callstacks,progress message.c > stacks-reference.log 2>&1
  $ awk '/^\[/ { p = /^\[eva:(alarm|progress)\] message\.c:[0-9]+:/ && !/Reusing/ } p' stacks-reference.log > stacks-reference.messages
  $ diff stacks.messages stacks-reference.messages

A fresh evaluation emits all the alarms of an expression before it tests
the threshold of -eva-stop-at-nth-alarm; a hit does not deliver its alarms
by evaluation. When the option is set, every supplied candidate is rejected
for stop-at-nth-alarm, and the body is analysed. The division of
threshold.c at line 7 has two alarms: with a threshold of 1, the analysis
stops after it has emitted both, as with caching disabled.

  $ EVA_TEST_CACHE_SAFETY=replay-out EVA_TEST_CACHE_SAFETY_STOP=1 frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -eva-msg-key cache threshold.c > stop.log 2>&1
  $ grep -E 'stop-at-nth-alarm|Stopping' stop.log
  [eva] User Error: Stopping at nth alarm
    call to body: lookup: rejected (entry 1: stop-at-nth-alarm); execution: interrupted; storage: none
  cache-rejected-stop-at-nth-alarm of body: 1
  $ grep '^| ' stop.log > stop.summary
  $ EVA_TEST_CACHE_SAFETY=reference-out EVA_TEST_CACHE_SAFETY_STOP=1 frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs threshold.c > stop-reference.log 2>&1
  $ grep '^| ' stop-reference.log > stop-reference.summary
  $ diff stop.summary stop-reference.summary

The hit sets again each red status of the body. In loop.c, with
-eva-slevel 10, the check mixed fails at two iterations of the loop of
body(1, 0), and holds at the third. A red context is a callstack where at
least one visit violates the property. The Safety part keeps the red
context of mixed at each of the two failures, in its place among the
other writes, and the hit sets both. The tables are those of the run with
caching disabled.

  $ EVA_TEST_CACHE_SAFETY=replay-out frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -eva-slevel 10 -eva-msg-key cache loop.c > loop.log 2>&1
  $ grep -E '^safety: red context|lookup: hit' loop.log
  safety: red context of property mixed at loop.c:9 (stmt 7), in the body
  safety: red context of property mixed at loop.c:9 (stmt 7), in the body
  safety: red context of alarm division_by_zero at loop.c:11 (stmt 11), in the body
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  $ grep '^| ' loop.log > loop.summary
  $ EVA_TEST_CACHE_SAFETY=reference-out frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -eva-slevel 10 loop.c > loop-reference.log 2>&1
  $ grep '^| ' loop-reference.log > loop-reference.summary
  $ diff loop.summary loop-reference.summary

The hit sets the red statuses and prints the messages in the order of the
analysis of the body. In abort-count.c, with -eva-slevel 10, the check mixed
fails at the first two iterations of the loop of body(1, 0), and holds at
the third. The first red context of mixed comes before the message of its
invalid status, the second before its second message. With the category
alarm set to abort, the analysis with caching disabled sets the first red
context, then stops at the first message; the hit at line 25 does the same.

  $ EVA_TEST_CACHE_SAFETY=replay-out EVA_TEST_CACHE_SAFETY_ALARM=abort frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -eva-warn-key alarm=inactive -eva-slevel 10 -eva-msg-key cache abort-count.c > abort-count.log 2>&1
  $ grep '^safety:' abort-count.log
  safety: red context of property mixed at abort-count.c:10 (stmt 7), in the body
  safety: status invalid of mixed, by Eva, in the body
  safety: message "check 'mixed' got status invalid." at abort-count.c:10, for a status invalid, in the body
  safety: red context of property mixed at abort-count.c:10 (stmt 7), in the body
  safety: message "check 'mixed' got status invalid." at abort-count.c:10, for a status invalid, in the body
  safety: status valid of mixed, by Eva, in the body
  safety: message "check 'mixed' got status valid." at abort-count.c:10, for a status valid, in the body
  safety: red context of alarm division_by_zero at abort-count.c:12 (stmt 11), in the body
  safety: alarm division_by_zero at abort-count.c:12 (stmt 11), status unknown by Eva, in the body
  $ grep -E 'lookup: hit|^analysis aborted' abort-count.log
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  analysis aborted
  $ grep '^| ' abort-count.log > abort-count.summary
  $ EVA_TEST_CACHE_SAFETY=reference-out EVA_TEST_CACHE_SAFETY_ALARM=abort frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -eva-slevel 10 abort-count.c > abort-count-reference.log 2>&1
  $ grep '^analysis aborted' abort-count-reference.log
  analysis aborted
  $ grep '^| ' abort-count-reference.log > abort-count-reference.summary
  $ diff abort-count.summary abort-count-reference.summary

An alarm or a status equal to one already recorded changes no table, and is
not recorded again. Each message of a status and each red context is
recorded, in order: the logger decides at each message whether to print it,
as in the analysis of the body. In repeat.c, the check never fails at the
three iterations of the loop. After the first, the status is the one
already recorded, and the red context and the message are recorded again.
Each message consults the history of the logger: the observer of the
collector counts 3 consultations at the hit, as in the analysis with
caching disabled. When the Safety part kept one message per text, it
counted 1 at the hit.

  $ EVA_TEST_CACHE_SAFETY=replay-out EVA_TEST_CACHE_SAFETY_HISTORY=count frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -eva-slevel 10 -eva-msg-key cache repeat.c > repeat.log 2>&1
  $ grep -E '^safety:|lookup: hit|^history consultations' repeat.log
  safety: red context of property never at repeat.c:8 (stmt 7), in the body
  safety: status invalid of never, by Eva, in the body
  safety: message "check 'never' got status invalid." at repeat.c:8, for a status invalid, in the body
  safety: red context of property never at repeat.c:8 (stmt 7), in the body
  safety: message "check 'never' got status invalid." at repeat.c:8, for a status invalid, in the body
  safety: red context of property never at repeat.c:8 (stmt 7), in the body
  safety: message "check 'never' got status invalid." at repeat.c:8, for a status invalid, in the body
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  history consultations: 3
  $ grep '^| ' repeat.log > repeat.summary
  $ EVA_TEST_CACHE_SAFETY=reference-out EVA_TEST_CACHE_SAFETY_HISTORY=count frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -eva-slevel 10 repeat.c > repeat-reference.log 2>&1
  $ grep '^history consultations' repeat-reference.log
  history consultations: 3
  $ grep '^| ' repeat-reference.log > repeat-reference.summary
  $ diff repeat.summary repeat-reference.summary

A client can change a setting between two occurrences of a message. In
second.c, the check later of body fails at the three iterations of its
loop. From the check trigger of other on, a client of the hooks of red
statuses sets the category alarm to abort at its second call. With caching
disabled, the second call of body stops at the second message of later.
The client is not audited: both calls of body reject the entries for
callback, with the same result. When the Safety part kept one message per
text and red clients were admitted, the hit gave out = 8.

  $ EVA_TEST_CACHE_SAFETY=same EVA_TEST_CACHE_SAFETY_SUPPLY=on EVA_TEST_CACHE_SAFETY_TRIGGER=red EVA_TEST_CACHE_SAFETY_ALARM2=1 frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -eva-warn-key alarm=inactive -eva-slevel 10 -eva-msg-key cache second.c > second.log 2>&1
  $ grep -E "call to body|Failure|^analysis aborted|^hits on" second.log
    call to body: lookup: rejected (entry 1: callback); execution: analysed; storage: refused (supplied-only); collector: refused (callback)
  [eva:alarm] second.c:9: Failure: check 'later' got status invalid.
    call to body: lookup: rejected (entry 1: callback); execution: interrupted; storage: none
  analysis aborted
  hits on body: 0
  $ grep '^| ' second.log > second.summary
  $ EVA_TEST_CACHE_SAFETY=same EVA_TEST_CACHE_SAFETY_TRIGGER=red EVA_TEST_CACHE_SAFETY_ALARM2=1 frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -eva-warn-key alarm=inactive -eva-slevel 10 -eva-msg-key cache second.c > second-reference.log 2>&1
  $ grep '^| ' second-reference.log > second-reference.summary
  $ diff second.summary second-reference.summary

An alarm already registered by another emitter keeps that emitter as its
owner. Eva emits its status on the alarm and registers nothing of its own,
in a delivery of the Safety part as in an analysis of body.

  $ EVA_TEST_CACHE_SAFETY=owner EVA_TEST_CACHE_SAFETY_OWNER=deliver frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer safety.c > owner-deliver.log 2>&1
  $ grep '^| ' owner-deliver.log
  | alarm division_by_zero at safety.c:11: owner Other; statuses: Eva unknown
  $ EVA_TEST_CACHE_SAFETY=owner EVA_TEST_CACHE_SAFETY_OWNER=analyse frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer safety.c > owner-analyse.log 2>&1
  $ grep '^| ' owner-analyse.log
  | alarm division_by_zero at safety.c:11: owner Other; statuses: Eva unknown

The owner depends on the order of the registrations: when the other emitter
registers the alarm after the delivery, Eva registered it first and owns
it.

  $ EVA_TEST_CACHE_SAFETY=owner EVA_TEST_CACHE_SAFETY_OWNER=late frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer safety.c > owner-late.log 2>&1
  $ grep '^| ' owner-late.log
  | alarm division_by_zero at safety.c:11: owner Eva; statuses: Eva unknown

The preconditions of the callee belong to the call site and are evaluated at
each call, a hit included. A hand-written entry of pre answers the call
pre(1) at line 18, where g = 0: the precondition is reported invalid at that
call, and no state reaches the end of main, as when pre is analysed. The
entry gives the check one a valid status. No state satisfies the
precondition, so the hit delivers nothing: before the passes at the end of
the analysis, one is never tried. The passes then mark one unreachable, as
with caching disabled.

  $ EVA_TEST_CACHE_SAFETY=precondition frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -eva-msg-key cache precondition.c > precondition.log 2>&1
  $ grep -E "^hits on|call to pre|precondition 'positive'|^before the passes" precondition.log
    call to pre: lookup: rejected (entry 1: key-differs); execution: analysed; storage: refused (supplied-only); collector: would-store
    call to pre: lookup: hit (entry 1); execution: not-analysed; storage: none
    function pre: precondition 'positive' got status invalid.
  before the passes: one is never tried
  hits on pre: 1
  $ grep -B 1 "precondition 'positive'" precondition.log | sed 's/ *$//'
  [eva:alarm] precondition.c:18: Warning:
    function pre: precondition 'positive' got status invalid.
  $ grep '^| ' precondition.log > precondition.summary
  $ cat precondition.summary
  | end of main: out: The computed state is bottom
  | global: red context of positive in pre :: precondition.c:18 <- main
  | precondition.c:10: status of one: valid
  | precondition.c:10: status of reachability of stmt precondition.c:10 in pre: invalid and reachable
  | precondition.c:16: status of specialization of positive at stmt 9: valid
  | precondition.c:18: red context of specialization of positive at stmt 11 in pre :: precondition.c:18 <- main
  | precondition.c:18: status of specialization of positive at stmt 11: invalid
  | precondition.c:6: status of positive: invalid
  | precondition.c:7-12: status of behavior default! in function pre: valid

With caching disabled, the statuses are the same, and the Safety part of
each analysed call of pre is empty: the statuses of the requires clause are
not part of the body.

  $ EVA_TEST_CACHE_SAFETY=precondition-reference frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -eva-msg-key cache precondition.c > precondition-reference.log 2>&1
  $ grep -E '^(Safety part|before the passes)' precondition-reference.log
  Safety part of pre :: precondition.c:16 <- main: none
  Safety part of pre :: precondition.c:18 <- main: none
  before the passes: one is never tried
  $ grep '^| ' precondition-reference.log > precondition-reference.summary
  $ diff precondition.summary precondition-reference.summary

A recording belongs to the project current when it starts; the collector
compares the count of the changes of the current project, kept by the
kernel, at its start and at its end. Each operation that changes the top of
the stack of projects counts the change when it makes it. Below, the
changes counted by some operations; loading two projects counts each step
that may change the current project.

  $ EVA_TEST_CACHE_SAFETY=project-count frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs next.c > project-count.log 2>&1
  $ grep ': [0-9]*$' project-count.log
  set_current of the current project: 0
  copy: 0
  on, left by an exception: 2
  remove of the current project: 1
  load_all of two projects: 5

During the loading of two projects, a hook of the change of project makes
current again the project that was current before the last change. The
loading then removes that project from the top of the stack, and another
one is current: the count differs from the one the hook saw. When the
removal was not counted, another project was current at the same count.

  $ EVA_TEST_CACHE_SAFETY=load-hook frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs next.c > load-hook.log 2>&1
  $ grep '^after the loading' load-hook.log
  after the loading: same project false, same count false
