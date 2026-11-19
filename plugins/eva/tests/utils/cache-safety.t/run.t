The Safety part of a cache entry holds the alarms, the statuses and the red
contexts emitted by its body. A hit delivers them at its own callstack, and
the kernel combines each status with those emitted before.

  $ dune build -j 8 --cache=disabled --root . test_cache_safety.cmxs

A first analysis from producer analyses body(1, 0) and stores its entry. At
x = 1, the assertion two is invalid and its branch stops; at y = 0, the
division is a sure alarm, with an unknown kernel status and a red context;
ok holds. Every write belongs to the body, with no frame above it.

  $ EVA_TEST_CACHE_SAFETY=replay frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -main producer -eva-msg-key cache safety.c > replay.log 2>&1
  $ grep -E '^(safety|after the reset|hits on)' replay.log
  safety: red context of property two at safety.c:9 (stmt 3), in the body
  safety: status invalid of two, by Eva, in the body
  safety: red context of alarm division_by_zero at safety.c:11 (stmt 7), in the body
  safety: alarm division_by_zero at safety.c:11 (stmt 7), status unknown by Eva, in the body
  safety: status valid of ok, by Eva, in the body
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

The preconditions of the callee belong to the call site and are evaluated at
each call, a hit included. A hand-written entry of pre answers the call
pre(1) at line 15, where g = 0: the precondition is reported invalid at that
call, and no state reaches the end of main, as when pre is analysed.

  $ EVA_TEST_CACHE_SAFETY=precondition frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -eva-msg-key cache precondition.c > precondition.log 2>&1
  $ grep -E "^hits on|call to pre|precondition 'positive'" precondition.log
    call to pre: lookup: rejected (entry 1: key-differs); execution: analysed; storage: refused (supplied-only); collector: would-store
    call to pre: lookup: hit (entry 1); execution: not-analysed; storage: none
    function pre: precondition 'positive' got status invalid.
  hits on pre: 1
  $ grep -B 1 "precondition 'positive'" precondition.log | sed 's/ *$//'
  [eva:alarm] precondition.c:15: Warning:
    function pre: precondition 'positive' got status invalid.
  $ grep '^| ' precondition.log > precondition.summary
  $ cat precondition.summary
  | end of main: out: The computed state is bottom
  | global: red context of positive in pre :: precondition.c:15 <- main
  | precondition.c:13: status of specialization of positive at stmt 5: valid
  | precondition.c:15: red context of specialization of positive at stmt 7 in pre :: precondition.c:15 <- main
  | precondition.c:15: status of specialization of positive at stmt 7: invalid
  | precondition.c:6: status of positive: invalid
  | precondition.c:7-9: status of behavior default! in function pre: valid

With caching disabled, the statuses are the same, and the Safety part of
each analysed call of pre is empty: the statuses of the requires clause are
not part of the body.

  $ EVA_TEST_CACHE_SAFETY=precondition-reference frama-c -no-autoload-plugins -load-module eva,test_cache_safety.cmxs -eva-msg-key cache precondition.c > precondition-reference.log 2>&1
  $ grep '^Safety part' precondition-reference.log
  Safety part of pre :: precondition.c:13 <- main: none
  Safety part of pre :: precondition.c:15 <- main: none
  $ grep '^| ' precondition-reference.log > precondition-reference.summary
  $ diff precondition.summary precondition-reference.summary
