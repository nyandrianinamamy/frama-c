# Sweeps and dependencies of a recorded body

## Lexical sweep in cvalue

**Claim.** The collector admits an exact lexical sweep only for inner
locals of its own body. It records the targets and treats each rewritten
holder as read and possibly written. For produced entries, the supplied
lookup checks that no binding in its current input may point to a swept
local and that the swept local itself is absent at entry.

**Kind.** OCaml obligation.

**Depends on.** [Frame and sweeps](frame.md#admission-condition-for-sweeps-of-own-locals),
[cvalue overlay](reuse-operation.md#reuse-sound-for-cvalue) and the
[instrumented footprint](body-access.md#whole-block-observations-and-exits).

**Source inspection.** `Iterator` leaves an inner scope on its Leave
edge. Top-level locals and formals are cleaned by the caller. The
cvalue path in `Locals_scoping.make_escaping_fundec` checks each target
against the function's locals and excludes the outer scope.
`Body_access.sweep` compares the function to the top of the recorder's
callstack. On a fresh nested analysis the caller inherits a `sweep`
refusal if its child performed a lexical sweep, even if the child could
store it. Outer cleanups inside a caller's recording refuse as well.
Free, reallocation, VLA and automatic allocation releases keep their
[allocation-family refusals](allocated-blocks.md). They do not register
lexical sweeps.

At a change of a cell, the cvalue sweep sets the escaping flag and removes
the targeted addresses. Its existing callback reports the holder before
the updated offsetmap is installed. The read makes the holder part of
the matching key and the possible write participates in the edge's exit
analysis. From a returning path the holder therefore belongs to the
overlay, whose binding comes from the post-sweep exit. A removed target
itself may be absent in that exit. The producer requires these targets
in the key, and permits their absence at the exit if absent at the
producing input. Merge then preserves absence when the current input
also lacks them.

`Sweep_access.clear_input` checks the producing input and, independently,
each current input used by `Supplied_entries.Lookup`. It checks every
explicit offsetmap cell and refuses if bases are unknown or intersect
the target set. Defaults for absent cells have no pointer in cvalue.
This is stronger than checking just the unchanged frame, and covers all
recorded targets even on nonreturning paths. At a prefix, a holder
initially without the target can only acquire a pointer to it through
body work. The usual write-coverage premise is needed to justify
reconstruction at that prefix. The guard addresses the recorded targets
only. It relies on the entry's trace covering the sweeps of the matched
execution and on the nonrecursive scope discipline. Eva uses a common
base for successive lifetimes of a source local, so inspecting only the
producing holder set or only the lexical declaration would not establish
the current-input condition. An enclosing invocation of the same function
and recursive traces refuse.

**Executed evidence.** `collector-effects.t` checks a body that writes
the address of its inner local to a global. The collector records the
target and the holder write. The produced exit and the supplied overlay
both contain the escaping marker. A synthetic current input extends that
same key with a previously absent holder of the address. The candidate
is rejected as `sweep`. The synthetic input exercises the guard without
evaluating or dereferencing an out-of-scope address in C. The test also
checks a callee's outer cleanup in its caller. `allocation-refusals.t`
covers free and automatic cleanup.

**Open.** Lookup in the replacement cache must apply this check even
when the key matches. The cvalue argument for the joint replay witness
and abstract execution coverage remains open. The fixture checks exit
reuse and the negative guard. It does not reconstruct an Inner query
or justify the caller-side outer cleanup.

## Calls and recursion

**Claim.** The collector records observed used functions with their call
modes. It refuses recursion and threaded mode.

**Kind.** OCaml obligation.

**Source inspection.** `Compute_functions.compute_call_with_target` and
the directive transfer report the resolved callee and its mode. A fresh
child's observed calls are unioned into the parent, even if the child
refuses. `Cache_call_trace` keeps the producing call trace of an observed
memexec entry for the current run. A hit on that entry reports its trace
to the enclosing recorder. The same reporting path uses the stored
dependencies of a supplied produced entry. A hit reports recursion when
its producing trace was refused as recursive or when its used functions
conflict with the current enclosing stack.
`Compute_functions.compute_call` reports recursive dispatch to
the parent, including dispatch to a specification. `Body_access.capture`
checks each recorded callee and the entry function against the enclosing
stack and propagates a recursive trace to the parent. The supplied lookup
repeats the stack check. A recording in Mthread, or with a non-main
thread identifier, records `threaded`. Other refusals can have higher
priority in the verdict.

**Executed evidence.** `collector-effects.t` checks a transitive fresh
call and recursion at several stack depths. It confirms a memexec hit
on `middle` and checks that the new enclosing body still records the
transitive call to `threaded`. It also checks a call-free body in Mthread.

**Open.** An entry produced without observations has only the directly
resolved call. The enclosing body refuses nested calls. Admission of
nested calls needs composition of their memory footprints and side-table
effects in addition to the call trace.

## Dynamic widening hints

**Claim.** A body that consults the effective dynamic hints records the
generation at entry. A body that evaluates a dynamic hint annotation
refuses. The supplied lookup compares the entry's stamp to the current
one.

**Kind.** OCaml obligation, a [`KeyedRead`](hit.md#side-table-obligations-for-skipped-work)
for the reader and an `UnsupportedAccess` for discovery.

**Source inspection.** `Widen.getWidenHints` marks the combined lookup
before consulting the per-function memo. A memo hit is a read too.
`Widen.dynamic_widen_hints_hook` refuses before evaluating annotated
lvalues and accumulating the discovered targets. When it joins new
thresholds into the dynamic table, it clears the same derived memo as
before. `Widen_type.adds_dynamic_hints` tests the added contributions
against previous per-base thresholds and the common defaults. A duplicate
or default threshold alone has no effect. A change advances the
project-local generation. The stamp also holds a fresh run identifier,
so equal generation numbers in two analyses compare different. The
generation recorded on a reader is an entry snapshot. If it differs at
the end of the body, the reader is refused, even if code outside the
reader caused the change. Nested observation propagates discovery refusal
and the fact that the body consulted hints. The generation conservatively
covers updates even when a particular function's static hints mask an
update.

**Executed evidence.** `collector-effects.t` runs both inventory
programs with legacy memexec disabled. In the reader program the reader
records generation 0 before discovery and generation 1 after it. The
control without discovery records 0 twice. In the writer program both
discoverers refuse and the later reader records generation 2. The
fresh reader result with discovery is `{13}` in both tests.

**Open.** The stamp is only for the current analysis. A persisted entry
would need its own validation of the effective hint contents. The
replacement cache must use the lookup check, including for nested hits.

## Ordered and opaque effects

**Claim.** The collector refuses the instrumented ordered and opaque
effects and reads of emission history.

**Kind.** OCaml obligation, [`UnsupportedAccess`](hit.md#side-table-obligations-for-skipped-work).

**Source inspection.** `Builtins_watchpoint` reports installation and
active checks. A watch installed after a candidate was produced can
affect a later call, so supplied lookup refuses when the table is active.
`Transfer_stmt.apply_special_directives` reports dumps before state
output or file numbering. The show directives keep their builtin
refusal. `Alarmset.emit_alarms` reports each stopping checkpoint under a
finite threshold. Even when the producing run completes, a new call can
arrive with more alarms accumulated. A body that never executes a
checkpoint does not refuse for this option alone. This is a conservative
test for whether stopping is possible. The existing iterator read of the
alarm-emission cache still refuses.

`Log.on_history_access` reports both the per-message once test and an
active once policy on an entire warning category. The category case can
suppress later messages with different text and always refuses. Two
partitioning feedback categories report work done during this run. Their
once-messages do not affect the analysis. The ordinary once warning for
an escaping local is identified by scope, target, holder and source
position. It has no callstack text. For the admitting sweep path the
holder binding is recorded, and re-emission of the same event within the
analysis is suppressed by the same logger history. These exceptions
apply to the per-message history only. A warning promoted to an error
or using a once category is outside that exception.

`Cvalue_callbacks` refuses by default when invoking an unclassified
call, call-result or statement callback. The existing explicit
classifications are limited to the named protocols or hooks that report
their own effects. `Hook.Opaque` also reports registered logger,
message-list, annotation-change and property callbacks at invocation.
The standard kernel message collector accounts for its own reporting.
`Traces_domain.Node.next` refuses whenever a trace node identity is
allocated in a recording.

**Executed evidence.** `collector-effects.t` checks watch installation
and a subsequent body with an active watch, a dump, a completed body
with a finite threshold, an unclassified logger listener and trace-node
allocation. `body-access.t` checks a registered call callback, an
interrupted alarm checkpoint, once categories, pointer comparisons,
partial unrolling and the previously instrumented ACSL messages.

**Open.** The refusal is based on instrumented accesses. Later cache
consumption must account for hook or warning configuration changes
between production and use and for extensions outside these hook
interfaces. Effects whose normal replay belongs to Safety or Reach
remain the responsibility of those parts. An interrupted body has no
completed storage verdict.
