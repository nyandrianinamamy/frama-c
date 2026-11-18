# Body access collector

## Whole-block observations and exits

**Claim.** The collector observes each fresh body by default. For the
supported transfers, R bounds the blocks read, W bounds possible C writes
and updates of cvalue bindings throughout the body, and W_exit bounds the
same writes and updates on paths that reach an exit. W_sure contains only
blocks fully overwritten by C assignments or initializers on every path to
an exit. The OCaml observer receives each completed observation before the
storage verdict. A memexec hit has no new body observation.

**Kind.** OCaml obligation.

**Depends on.** [The call-cache seam](call-cache-seam.md) for the separation
of lookup, body execution and storage.

**Symbols.** `Compute_functions.Make.compute_and_cache_call`,
`Body_access.capture`, `Evaluation.Make.reduced_lval_to_loc`,
`Cvalue_queries.extract_lval`, `Cvalue_queries.backward_location`,
`Cvalue_transfer.copy_one_loc`, `Cvalue_transfer.reduce`,
`Cvalue_domain.State.assign`, `Cvalue_domain.State.initialize_variable`,
`Cvalue_domain.State.enter_scope`, `Cvalue_domain.State.leave_scope`,
`Iterator.Make_Dataflow.process_edge`, `Body_access.transfer`,
`Body_access.finish_paths`.

**Argument.** Each body has a scoped recorder. Normal return and exceptions
restore the enclosing recorder. The observer receives the completed record
with recording suspended. Cvalue reports reads at scalar and aggregate
queries, copies and backward-location queries. The evaluator checks locations
before validity narrowing and reports values that can designate blocks. Raw
values are also checked at scalar reads and in copied offsetmaps, including a
pointer copied without dereferencing it. The cvalue assignment and initializer
report possibly written blocks. An exact write contributes sure bits within
its transfer. A changed valuation binding, scope binding installation
(including `-eva-initialized-locals`, the return slot and the uninitialized
binding of a volatile local) or scope binding removal only contributes a
possible write. Changed ACSL predicate bindings
contribute Top to the possible writes, in addition to the clause's refusal.

The cvalue audit covers the following state updates.

- `backward_location` computes possible locations and `reduce_further`
  returns no further cvalue reductions. Valuation updates during `assume`,
  assignment, call setup and post-call actual reduction all use
  `Cvalue_transfer.reduce`.
- C initializers and the assignment to the return slot use the instrumented
  initialization and assignment paths. Global initialization and the main
  entry formals precede the body. The callee's formals are bound before its
  recorder, and the callee's outer locals, formals and return slot are
  removed by the caller according to the call protocol. These changes fall
  within the caller's unsupported nested-call footprint, when applicable.
  Inner scope removal is scoped to the body. Its escape sweep and automatic
  allocation cleanup are refused.
- `logic_assign`, including initialization by type for specification
  results, is covered by the refusal and Top bounds for specification,
  builtin and statement-contract effects. Recursive removal, substitution
  and merge are outside the supported collector domain. Normal cvalue call
  finalization returns the post-state. Memexec merge is a lookup operation
  and contributes no fresh body.
- Domain joins, widening and narrowing compute abstract control-flow
  states. The write bounds describe transfers on the graph. They do not
  count each change of abstract representation as a program write.

The iterator records the writes of each transfer that produced a successor.
It joins possible blocks and intersects sure bits across observations of the
same edge. W retains writes from the entire body. A backward walk from the
return vertex yields W_exit. Forward propagation starts with no written bits
at entry, accumulates bits across successive exact writes and intersects the
bits at joins. Only a block whose full known validity range is covered at
return enters W_sure. When the body has no exit state, W_exit and W_sure are
empty. May sets can be Top when an unsupported operation has unknown
accesses. Unknown writes outside a transfer use W as the bound on W_exit and
provide no sure blocks.

**Evidence.** Source inspection. The OCaml observer in
[`body-access.t`](../../../plugins/eva/tests/utils/body-access.t/run.t)
asserts the sets for `q = p`, a write followed by an infinite loop, full
overwrites on both returning branches, and partial writes that cover one
element or both elements of an array. The fixture checks a copied
allocation address, a guard reduction on a returning path, an initialized
local binding and the loss of correlation between two guards.

**Open.** The graph merges observations at the automaton vertices. It may
connect edges that fired on different abstract paths, including at loops,
widening and late joins. Thus W_exit is an upper bound and W_sure a lower
bound even when Eva partitions the states.
The collector does not implement a reusable Exit part.
The cost of recording is measured on three tests only: with recording on,
the median wall time of `matrix` rose by about a quarter over the base
binary. The update of an edge record at every successful transfer is a
candidate cause and has no fast path when its writes are unchanged.

## Refusal and reporting

**Claim.** The collector gives one verdict per completed observed body,
including with memexec disabled. It records unsupported operation families
and gives the first reason in its documented priority order. A verdict does
not participate in memexec lookup, storage, argument reduction or dispatch.

**Kind.** OCaml obligation.

**Depends on.** [Whole-block observations and exits](#whole-block-observations-and-exits)
and [the call-cache seam](call-cache-seam.md).

**Symbols.** `Body_access.Result.refusal_id`, `Body_access.verdict`,
`Call_cache.Make.store`, `Transfer_stmt.Make.call`,
`Compute_functions.Make.compute_call_with_target`,
`Transfer_logic.Make.create_from_spec`, `Transfer_logic.Make.interp_annot`,
`Locals_scoping.make_escaping_fundec`, `Builtins_malloc.free_aux`.

**Argument.** The priority order is `indirect-call`, `builtin`, `sweep`,
`contract`, `annotation`, `nested-call`, `allocated-block`,
`footprint-top`, then `side-table`. The observer receives all reasons.
Indirect targets refuse both at the call transfer and at entry of a body
reached through an indirect call. A nested call refuses its enclosing body
whether resolved to a fresh body, a hit, a specification or a builtin.
The collector does not compose child observations in this slice. An
unsupported contract or annotation read has a Top bound. Used builtins and
sweeps mark their active recorder. Allocation targets and unknown sets are
checked independently of which accesses appear in the matching sets. The
collector also refuses recursive invocations, concurrent analysis and any
domain structure other than a single unrestricted cvalue domain.

The call-site `requires` checks execute outside the fresh callee body's
observations. Eva interleaves them with behavior selection and the handling
of `assumes` clauses. The recorder is suspended during the `requires`
checks to preserve that order and still observe behavior selection,
`assumes`, and the body's postconditions and statement contracts. It is
also suspended while the statuses of the `requires` clauses of an inactive
behavior are emitted; the statuses of its `ensures` clauses stay in the
observation.

Recording is on by default. The internal option `-eva-no-cache-collect`
disables it for subsequent bodies. The iterator selects recording and
yield behavior once per body. The read and designation hooks return
before computing a footprint when recording is off. Keeping the switch
out of the ordinary help preserves its oracle. The `cache` message reports the
collector verdict beside the memexec storage disposition.
`collector-would-store` and `collector-refused-REASON` count these verdicts.
The collector does not count an interrupted body or a body skipped on a hit.

**Evidence.** Source inspection. The
[`body-access.t`](../../../plugins/eva/tests/utils/body-access.t/run.t)
fixture exercises both option settings, the OCaml observation before the
verdict, and the diagnostic and count of the relevant refusal families.
[`cache_dispositions.c`](../../../plugins/eva/tests/value/cache_dispositions.c)
continues to exercise memexec storage and a matching hit through the seam.
The cram fixture also asserts one observation and one memexec hit for two
calls to a leaf, checks that two recorders unwind after an alarm stops the
analysis, and checks that a leaf's `requires` alone leaves its verdict
would-store. The mthread case checks that
[`dev/collector-counts.sh`](../../../dev/collector-counts.sh) uses one
cumulative statistics snapshot per analysis, across repeated `Computed`
notifications, and matches the verdict log and the final statistics.

**Open.** Contract and annotation read coverage, child composition and
replay are pending. A would-store verdict does not establish that a body can
be reused in another context.

## Side tables and recorded joins

**Claim.** The body verdict accepts the observed write-only joins of the
analysis. The record names their classes. Callwise Inout and From run through
their existing protocols outside the body observations.

**Kind.** OCaml obligation.

**Depends on.** [Refusal and reporting](#refusal-and-reporting).

**Symbols.** `Body_access.record`, `Iterator.record_fireable`,
`Iterator.Make_Dataflow.merge_results`, `Function_calls.register_call`,
`Alarmset.register_alarm`, `Alarmset.already_emitted`,
`Transfer_logic.emit_status`, `Inout_access.register`,
`Locals_scoping.remember_bases_with_locals`,
`Cvalue_callbacks.register_call_hook`, `Cvalue_callbacks.register_call_results_hook`,
`Widen.getWidenHints`, `Builtins_watchpoint.watch_hook`.

**Argument.** Program and AST-derived information, effective contracts,
configuration, builtin selection, static widening hints, return slots and
initial-state blocks are fixed for the observed run. Evaluating a contract is
a separate refusal involving reads of program memory.

Reached statements, states, caller sites, guard outcomes, alarms, statuses,
read and write zones, and holder sets are reported as recorded when observed.
The ordered alarm-stop check with a finite threshold and the iterator's
consultation of alarm emission history refuse. The combined widening lookup
refuses because it includes the mutable dynamic hints. A statement that
evaluates a dynamic hint and an active watchpoint also refuse. Call hooks
without a classification refuse by default. The existing callwise protocols
and derived reporting hooks are declared at registration. This keeps their
own queries out of the collector without changing their computation. For a
given sequence of executed transfers, the observation is independent of
callwise Inout. A callwise output can let Eva reduce an actual after a call
and hence change which transfers run in the caller.

`Origin.History` reports access at the table operations, including when
pointer arithmetic registers a garbled temporary and when a join consults
origin IDs. An observed access refuses as `side-table`. Mthread uses
the same dispatch protocol and refuses while enabled.

**Evidence.** Source inspection. The
[`body-access.t`](../../../plugins/eva/tests/utils/body-access.t/run.t)
fixture compares asserted observation fields on the same input with Inout
loaded and unloaded, and checks an input that Inout produces. Paired caller
runs show a builtin reached without Inout and pruned with Inout. The fixture
asserts the recorded join classes, including guards and alarms, and exercises
refusals for a temporary origin, an unclassified callback and cvalue
restricted by function.

**Open.** The classes in the observation do not carry replay payloads.
Their Safety and Reach replay is pending. The collector reports unsupported
accesses at instrumented paths and at unclassified callback boundaries.
The side-table audit still needs to cover transitive accesses in helpers and
persistent memos, and to account for changes between a producer and a future
lookup.
