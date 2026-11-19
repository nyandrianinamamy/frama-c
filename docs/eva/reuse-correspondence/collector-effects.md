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

On a cell with a finite set of bases, the exact cvalue sweep removes
the swept bases and sets the escaping flag if it removes any. This
applies both to address maps and to garbled values with known bases.
For a value with unknown bases, the sweep sets the escaping flag and
keeps the value with all bases. The sweep's callback reports the holder
before the updated offsetmap is installed. The read makes the holder part of
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
the target set. It also refuses an explicit binding for a target. Defaults for absent cells have no pointer in cvalue.
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
is rejected as `sweep`. Offset ranges, garbled pointers, unknown bases
and an escaping flag with a remaining pointer also reject both
candidates. An escaping marker alone admits the first. The synthetic
inputs avoid dereferencing an out-of-scope address in C. A prebound
target changes the key and also fails the independent producing-input
guard. A matching key with a preexisting holder likewise fails that
producer guard. The fixture also checks an own outer scope and a callee's
outer cleanup in its caller. `allocation-refusals.t`
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
to the enclosing recorder. A supplied hit contributes the used functions
from the winning entry's stored dependencies. A legacy trace reports
recursion when
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
transitive call to `threaded`. It checks the producing trace returned
by a supplied hit, rejection of both candidates on a recursive stack,
and refusal when a formerly nonrecursive hit trace is included in a
conflicting caller's recording. It also checks a call-free body in Mthread.

**Open.** An entry supplied without a producing observation contributes
its directly resolved call and makes the enclosing observation refuse as
`nested-call`. The collector can produce enclosing entries with nested
work. Until delivery exists, the supplied lookup guards both constructors
by inspecting the subject's body for calls.
[Nested call collection](nested-calls.md#composition-along-the-observed-path).

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
project-local generation. The stamp also holds a fresh run identifier
within the process, so equal generation numbers in two analyses in that
process compare different. The
generation recorded on a reader is an entry snapshot. If it differs at
the end of the body, the reader is refused, even if code outside the
reader caused the change. Nested observation propagates discovery refusal
and the fact that the body consulted hints. The generation conservatively
covers updates even when static hints mask them for every function.
A global static threshold annotated in an uncalled function is one
example. Advancing the stamp in this case can lose reader hits without
changing analysis results.

**Executed evidence.** `collector-effects.t` runs both inventory
programs with legacy memexec disabled. In the reader program the reader
records generation 0 before discovery and generation 1 after it. The
control without discovery records 0 twice. In the writer program both
discoverers refuse and the later reader records generation 2. The
fresh reader result with discovery is `{13}` in both tests. Discovering
a default threshold leaves both reader generations at zero. Lookup
falls through a stale candidate to the newer one, and a second run
refuses the first run's entries even at the same numeric generation.
An update during a recording after a hint read refuses that reader.

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
The watch table is process-global. A watch installed in another project
also causes this conservative refusal and can cost hits in the original
project.
`Transfer_stmt.apply_special_directives` reports dumps before state
output or file numbering. The show directives keep their builtin
refusal. Both kinds of directive report Top reads and dependencies. `Alarmset.emit_alarms` reports each stopping checkpoint under a
finite threshold, sampled on either side of emission. Even when the
producing run completes, a new call can arrive with more alarms
accumulated. A body that never executes a checkpoint does not refuse
for this option alone. Refusing at any finite threshold is conservative.
Eva makes the stopping decision with the threshold read after emission,
so a listener can raise it before the decision. The existing iterator
read of the alarm-emission cache still refuses.

`Log.on_history_access` reports both the per-message once test and an
active once policy on an entire warning category. The category case can
suppress later messages with different text and always refuses. Two
partitioning feedback categories report work done during this run. Their
once-messages do not affect the analysis. The ordinary once warning for
an escaping local is identified by scope, target, holder and source
position. It has no callstack text. For the admitting sweep path the
holder binding is recorded, and re-emission of the same event within the
analysis is suppressed by the same logger history. The message of a
status of the body is also admitted: the Safety part records it at each
emission, and a hit prints each occurrence again through the logger,
which makes the per-message test again at the hit
([Safety at a hit](safety.md#a-hit-delivers-the-safety-part-as-recorded-joins)).
These exceptions apply to the per-message history only. A warning promoted
to an error or using a once category is outside that exception.

The audit of callbacks and hook registrations in this change is below.
A refusal is recorded on invocation during a body, including a
consultation that an ordinary history subscriber observes even when the
logging event would otherwise be admitted.

- The collector's policy observer is the only audited client of
  `Log.on_history_access`. Ordinary subscribers invoke `Hook.Opaque` and
  refuse with `callback`.
- The standard kernel message collector is the only audited listener
  registered with `Log.add_listener`. The error flag of the parser
  (`Errorloc.set_error`) is the only audited listener registered with the
  `register` function of a plug-in's logger: it listens to the errors
  and failures of the kernel's channel, which a hit does not emit
  ([Safety at a hit](safety.md#a-hit-runs-no-client-that-is-not-audited)).
  Other listeners, of
  either function, refuse with `callback`.
- Any client of the kernel message-list hook `Messages.add_hook` refuses
  with `callback`, including a client of the audited message collector.
- Any client of `Annotations.add_hook_on_change` refuses with `callback`,
  the server's included: it is registered with `audited`, which concerns
  the lookup only
  ([Safety at a hit](safety.md#a-hit-runs-no-client-that-is-not-audited)),
  and its invocation still reports to `Hook.Opaque`. The server's listener
  is a no-op without a server. Admitting its invocation in a body is
  deferred. The reviewed suite comparison attributed 160 lost would-store
  verdicts and 153 lost produced entries to callback refusals, measured
  before the admission of the messages of statuses; the clients of red
  status hooks were refused then, as they are again.
- Any client of the `Property_status` add, remove and status-update hooks
  refuses with `callback`.
- Any client of `Red_statuses.register_hook` refuses with `callback`.
  An earlier version of the Safety part admitted these clients, since a
  hit runs the hook again. A client that adds a red status of its own, or
  that does so only in the analysis that produced an entry, still tells a
  hit from an analysis of the body, and the refusal was restored.
- The `Cvalue_callbacks` call, call-result and statement hooks admit
  audited clients only through the existing cache protocols and classified
  callbacks that account for their effects. Each unclassified client
  refuses with `callback`.
- The collector's `Hook.Opaque.on_call` observer records `callback`
  before every wrapped invocation. Extra observers run only on those
  already refused invocations during a body.
- The collector registers its observers of the kernel with `audited`:
  those of `Hook.Opaque.on_call`, of `Origin.on_history_access`, of
  `Log.on_history_access`, and of the reads of the metadata and the
  updates of the validity of allocated blocks
  (`Base.observe_metadata_reads`, `Base.observe_validity_updates`). The flag
  concerns the lookup only. Outside a recording these observers refuse
  nothing and write only in the counters of the collector; the observers of
  `Base` are installed while a body is recorded and run the observer that
  they replaced. A hit can run one of them: the observer of `Hook.Opaque`,
  through the client of the server on the annotations. A hit evaluates
  nothing, and no regression makes it run the observer of the metadata,
  which ran in the check of the preconditions when a hit made one. No
  other client of
  the tree uses the flag; at the lookup, any client registered without it
  rejects every supplied candidate with `callback`
  ([Safety at a hit](safety.md#a-hit-runs-no-client-that-is-not-audited)).
- `Body_access.on_result` runs with recording suspended, after the
  observed body finishes. A hit runs none of its observers; one registered
  without `audited` rejects every supplied candidate with `callback`, as
  does an observer of `Safety_part.on_result` registered without it.

These refusals concern the clients invoked during a body. At the lookup,
a client that is not audited, registered at any time before the lookup on
one of the hooks a hit runs, rejects every supplied entry with `callback`,
so that no such client runs during a hit. The hooks on the removal of a
property are not among them: the lookup tests the hooks on a new property
and on a new status only, the kernel itself registers a removal hook, and
such a client refuses only when it is invoked during a recording. Neither
a hit nor the analysis of a body removes a property: by a search of the
tree, the removals run in the copy visitors, the inlining, the typing, the
removal of the alarms of an emitter and the export of the results of Eva,
outside a call
([Safety at a hit](safety.md#a-hit-runs-no-client-that-is-not-audited)).

`Traces_domain.Node.next` refuses whenever a trace node identity is
allocated in a recording.

**Executed evidence.** `collector-effects.t` checks watch installation
before statement transfer, an active watch during transfer and two
lookup refusals after a watch is installed in another project. It also
checks a state dump, a file dump and its first numbered file, trace-node
allocation, an unclassified logger listener, and red and history
clients that run once each: each body is refused with `callback`, and no
entry is produced. With
collection disabled, the threshold-raising listener lets Eva finish
with memexec enabled or disabled. `body-access.t` checks a registered
call callback, an interrupted alarm checkpoint, an isolated once-category
notification, pointer comparisons, partial unrolling and the previously
instrumented ACSL messages.

**Open.** The refusal is based on instrumented accesses. A client
registered between the production and the use of an entry rejects it at
the lookup; extensions outside these hook interfaces are not covered. The
lookup rejects an entry when the status of a warning category changed
before it
([Safety at a hit](safety.md#the-settings-that-decide-the-alarms-and-messages-are-those-of-each-hit)).
Effects whose normal replay belongs to Safety or Reach remain the
responsibility of those parts. An interrupted body has no
completed storage verdict.
