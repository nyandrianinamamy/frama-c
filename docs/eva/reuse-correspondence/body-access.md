# Body access collector

## Whole-block observations and exits

**Claim.** The collector observes each analysed body with
`-eva-cache-collect`. For supported C accesses, its may sets bound the
blocks read and written, and its sure set contains blocks fully overwritten
on every path to an exit. The OCaml observer receives the result of each
completed body before the storage verdict. A memexec hit has no new body
observation.

**Kind.** OCaml obligation.

**Depends on.** [The call-cache seam](call-cache-seam.md) for the separation
of lookup, body execution and storage.

**Symbols.** `Compute_functions.Make.compute_and_cache_call`,
`Body_access.capture`, `Evaluation.Make.reduced_lval_to_loc`,
`Cvalue_queries.extract_lval`, `Cvalue_queries.backward_location`,
`Cvalue_transfer.copy_one_loc`, `Cvalue_domain.State.assign`,
`Cvalue_domain.State.initialize_variable`, `Iterator.Make_Dataflow.process_edge`,
`Body_access.transfer`, `Body_access.finish_paths`.

**Argument.** Each body has a scoped recorder. Normal return and exceptions
restore the enclosing recorder. The observer receives the completed record
with recording suspended. Cvalue reports reads at scalar and aggregate
queries, copies and backward-location queries. The evaluator checks locations
before validity narrowing and reports values that can designate blocks. Raw
values are also checked at scalar reads and in copied offsetmaps, including a
pointer copied without dereferencing it. The cvalue assignment and initializer
report possibly written blocks. State narrowing and scope binding creation
are part of the transfer or scope protocol. They are outside the designated
write set.

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
element or both elements of an array. It also checks a copied allocation
address and a refusal on the body that read it.

**Open.** The graph merges observations at the automaton vertices. It may
connect edges that fired on different abstract paths, including after
partitioning or widening. W_exit may therefore include extra blocks and
W_sure may omit blocks that would be justified by a path-sensitive argument.
The collector does not implement a reusable Exit part.

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
collector also refuses recursive invocations, non-cvalue products and
concurrent analysis.

The collector is off by default. `-eva-cache-collect` enables observations
for bodies analysed after it is set. The `cache` message reports the
collector verdict beside the memexec storage disposition.
`collector-would-store` and `collector-refused-REASON` count these verdicts.
The collector does not count an interrupted body or a body skipped on a hit.

**Evidence.** Source inspection. The
[`body-access.t`](../../../plugins/eva/tests/utils/body-access.t/run.t)
fixture exercises both option settings, the OCaml observation before the
verdict, and the diagnostic and count of the relevant refusal families.
[`cache_dispositions.c`](../../../plugins/eva/tests/value/cache_dispositions.c)
continues to exercise memexec storage and a matching hit through the seam.

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
own queries out of the collector without changing their computation.
Mthread uses the same dispatch protocol and refuses while enabled.

**Evidence.** Source inspection. The
[`body-access.t`](../../../plugins/eva/tests/utils/body-access.t/run.t)
fixture compares asserted observation fields on the same input with Inout
loaded and unloaded. It asserts classifications for a subset of the recorded
joins and exercises the default refusal of an unclassified callback.

**Open.** The classes in the observation do not carry replay payloads.
Their Safety and Reach replay is pending. The collector reports unsupported
accesses at instrumented paths and at unclassified callback boundaries.
The side-table audit still needs to cover transitive accesses in helpers and
persistent memos, and to account for changes between a producer and a future
lookup. Equality of a collector result with and without Inout is tested on
the same body and transfer path. The engine can choose different transfer
paths after a nested call when a callwise Inout result is available.
