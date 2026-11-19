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
line 26 is a hit, and its body is not analysed.

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
statements, and a hit saves none in the body of the called function. Until
a hit delivers the statements it reaches, the passes draw no conclusion in a
function a call of which was answered by a hit in the analysis: the
refinement of the statuses of alarms gives no status there, and the marking
of dead code marks nothing unreachable. The statuses delivered by the hit
stay as delivered.

In passes.c, the entry of body(1, 0) comes from an analysis from producer,
and answers the call at line 35 of main; body(2, 1) is analysed. Executed
from main, the second call divides 100 by y = 0 at line 13 when v reads a
non-zero value, and reaches the assertion one when v reads a non-zero value
at line 10. The analysed call alone never divides by zero, and never reaches
one. Without the restriction, the refinement gave the division alarm the
final status valid, and one was marked unreachable. The final status below
is that of the analysis from producer, where body(1, 0) is analysed. The
record of the functions answered by a hit is reset with the analysis, here
by a change of the entry point.

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

The summary of the analysis counts every statement of body as reached. It
can count more than with caching disabled: here the loop at line 14, which
no call reaches, is counted. The first line is that of the analysis from
producer.

  $ grep 'statements reached' passes.log
    In these functions, 11 statements reached (out of 12): 92% coverage.
    In these functions, 15 statements reached (out of 15): 100% coverage.
  $ grep 'statements reached' passes-reference.log
    In these functions, 14 statements reached (out of 15): 93% coverage.

In the reverse order, body(1, 0) is analysed, and the entry of body(2, 1),
produced from producer_safe, answers the call at line 44. Without the
restriction, the refinement read the states of the analysed call, where
y = 0, and made the alarm invalid; with caching disabled it is unknown.

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
a function, and gives them a valid status. It generates none in a function
a call of which was answered by a hit: without the restriction, it asserted
\false at lines 10 and 14 of body, reached through the hit, and x == 2.

  $ EVA_TEST_CACHE_SAFETY=replay-out EVA_TEST_CACHE_SAFETY_EXPORT=on frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer passes.c > export.log 2>&1
  $ grep 'export' export.log
  annotations exported in body: 0

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
  $ EVA_TEST_CACHE_SAFETY=replay-out frama-c -no-autoload-plugins -load-module eva,metrics,test_cache_safety.cmxs -main producer -eva-msg-key cache passes.c > metrics.log 2>&1
  $ grep -E 'call to body|^hits on' metrics.log
    call to body: lookup: no-candidate; execution: analysed; storage: refused (no-inout); collector: would-store
    call to body: lookup: rejected (entry 1: consumer); execution: analysed; storage: refused (supplied-only); collector: would-store
    call to body: lookup: rejected (entry 1: consumer); execution: analysed; storage: refused (supplied-only); collector: would-store
  hits on body: 0

A hit records the called function alone among those whose statements have
no state: an entry is refused for a body that may call a function that has
a body.

  $ EVA_TEST_CACHE_SAFETY=nested frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs safety.c > nested.log 2>&1
  $ grep '^refused' nested.log
  refused: Supplied_entries.supply: the body of outer may call a function that has a body

A recording belongs to the project current when it starts. A hook of red
statuses enters a second project with Project.on the first time it runs,
during the analysis of body from producer, and sets a red status there.
Each recording in progress, of body and of producer, is refused for
project-switch, and no entry is stored. The analysis from main has no
candidate, and its tables are those of the run with caching disabled and
the same hook.

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
runs, a hook of red statuses enters the first project with Project.on and
leaves it, without writing there. Each recording in progress is refused for
project-switch, and no entry is stored. The analysis from main, in the copy,
has no candidate, and its tables are those of the run with caching disabled
in the same setting.

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

  $ EVA_TEST_CACHE_SAFETY=replay-out EVA_TEST_CACHE_SAFETY_OVERFLOW=on frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -no-warn-signed-overflow -eva-msg-key cache overflow.c > overflow.log 2>&1
  $ grep -B 1 'lookup: hit' overflow.log | sed 's/ *$//'
  [eva:cache] overflow.c:19:
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  $ grep '^| ' overflow.log > overflow.summary
  $ EVA_TEST_CACHE_SAFETY=reference-out frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs overflow.c > overflow-reference.log 2>&1
  $ grep '^| ' overflow-reference.log > overflow-reference.summary
  $ diff overflow.summary overflow-reference.summary
  1a2,3
  > | overflow.c:8: red context of alarm signed_overflow in body :: overflow.c:19 <- main
  > | overflow.c:8: status of alarm signed_overflow: invalid
  [1]

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

The hooks of red statuses run each time a red status is set. In loop.c,
with -eva-slevel 10, the check mixed fails at two iterations of the loop of
body(1, 0), and holds at the third. A red context is a callstack where at
least one visit violates the property. The Safety part keeps the red
context of mixed at each of the two failures, in its place among the
other writes, and the hit runs the hooks twice. A hook that counts its
calls is called as many times as with caching disabled.

  $ EVA_TEST_CACHE_SAFETY=replay-out EVA_TEST_CACHE_SAFETY_COUNT=red frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -eva-slevel 10 -eva-msg-key cache loop.c > loop.log 2>&1
  $ grep -E '^safety: red context|lookup: hit|^red hook calls' loop.log
  safety: red context of property mixed at loop.c:9 (stmt 7), in the body
  safety: red context of property mixed at loop.c:9 (stmt 7), in the body
  safety: red context of alarm division_by_zero at loop.c:11 (stmt 11), in the body
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  red hook calls: 5
  $ grep '^| ' loop.log > loop.summary
  $ EVA_TEST_CACHE_SAFETY=reference-out EVA_TEST_CACHE_SAFETY_COUNT=red frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -eva-slevel 10 loop.c > loop-reference.log 2>&1
  $ grep '^red hook calls' loop-reference.log
  red hook calls: 5
  $ grep '^| ' loop-reference.log > loop-reference.summary
  $ diff loop.summary loop-reference.summary

The hit runs the hooks of red statuses and prints the messages in the order
of the analysis of the body. In abort-count.c, with -eva-slevel 10, the
check mixed fails at the first two iterations of the loop of body(1, 0),
and holds at the third. The first red context of mixed comes before the
message of its invalid status, the second after it. With the category alarm
set to abort, the analysis with caching disabled runs the hook once, then
stops at that message; the hit at line 25 does the same. Before the red
contexts were kept in order, the hit ran the hook twice before it stopped.

  $ EVA_TEST_CACHE_SAFETY=replay-out EVA_TEST_CACHE_SAFETY_ALARM=abort EVA_TEST_CACHE_SAFETY_COUNT=red frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -eva-warn-key alarm=inactive -eva-slevel 10 -eva-msg-key cache abort-count.c > abort-count.log 2>&1
  $ grep '^safety:' abort-count.log
  safety: red context of property mixed at abort-count.c:10 (stmt 7), in the body
  safety: status invalid of mixed, by Eva, in the body
  safety: message "check 'mixed' got status invalid." at abort-count.c:10, for a status invalid, in the body
  safety: red context of property mixed at abort-count.c:10 (stmt 7), in the body
  safety: status valid of mixed, by Eva, in the body
  safety: message "check 'mixed' got status valid." at abort-count.c:10, for a status valid, in the body
  safety: red context of alarm division_by_zero at abort-count.c:12 (stmt 11), in the body
  safety: alarm division_by_zero at abort-count.c:12 (stmt 11), status unknown by Eva, in the body
  $ grep -E 'lookup: hit|^analysis aborted|^red hook calls' abort-count.log
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  analysis aborted
  red hook calls: 1
  $ grep '^| ' abort-count.log > abort-count.summary
  $ EVA_TEST_CACHE_SAFETY=reference-out EVA_TEST_CACHE_SAFETY_ALARM=abort EVA_TEST_CACHE_SAFETY_COUNT=red frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -eva-slevel 10 abort-count.c > abort-count-reference.log 2>&1
  $ grep -E '^analysis aborted|^red hook calls' abort-count-reference.log
  analysis aborted
  red hook calls: 1
  $ grep '^| ' abort-count-reference.log > abort-count-reference.summary
  $ diff abort-count.summary abort-count-reference.summary

An alarm, a status or a message equal to one already recorded changes no
table and prints nothing again, and is not recorded again. Red contexts set
in a row, with no other write recorded between them, form one write with
their number. In repeat.c, the check never fails at the three iterations of
the loop: after the first, the status and the message are those already
recorded, and the next two red contexts form one write. The hook runs three
times, as with caching disabled.

  $ EVA_TEST_CACHE_SAFETY=replay-out EVA_TEST_CACHE_SAFETY_COUNT=red frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -eva-slevel 10 -eva-msg-key cache repeat.c > repeat.log 2>&1
  $ grep -E '^safety:|lookup: hit|^red hook calls' repeat.log
  safety: red context of property never at repeat.c:8 (stmt 7), in the body
  safety: status invalid of never, by Eva, in the body
  safety: message "check 'never' got status invalid." at repeat.c:8, for a status invalid, in the body
  safety: red context of property never at repeat.c:8 (stmt 7), set 2 times, in the body
    call to body: lookup: hit (entry 1); execution: not-analysed; storage: none
  red hook calls: 3
  $ EVA_TEST_CACHE_SAFETY=reference-out EVA_TEST_CACHE_SAFETY_COUNT=red frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -eva-slevel 10 repeat.c > repeat-reference.log 2>&1
  $ grep '^red hook calls' repeat-reference.log
  red hook calls: 3

An alarm already registered by another emitter keeps that emitter as its
owner. Eva emits its status on the alarm and registers nothing of its own,
in a delivery of the Safety part as in an analysis of body.

  $ EVA_TEST_CACHE_SAFETY=owner EVA_TEST_CACHE_SAFETY_OWNER=deliver frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer safety.c > owner-deliver.log 2>&1
  $ grep '^| ' owner-deliver.log
  | alarm division_by_zero at safety.c:11: owner Other; statuses: Eva unknown
  $ EVA_TEST_CACHE_SAFETY=owner EVA_TEST_CACHE_SAFETY_OWNER=analyse frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer safety.c > owner-analyse.log 2>&1
  $ grep '^| ' owner-analyse.log
  | alarm division_by_zero at safety.c:11: owner Other; statuses: Eva unknown

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
