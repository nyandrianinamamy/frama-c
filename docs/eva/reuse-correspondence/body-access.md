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
`Body_access.finish_paths`, `Body_access.designate_cells`.

**Argument.** Each body has a scoped recorder. Normal return and exceptions
restore the enclosing recorder. The observer receives the completed record
with recording suspended. Cvalue reports reads at scalar and aggregate
queries, copies and backward-location queries. The evaluator checks locations
before validity narrowing and reports values that can designate blocks. A
scalar or backward-location load joins the offsetmap cells of its range into
one value, and the join can drop a pointer: beside an uninitialized cell, the
combined value is uninitialized and designates nothing. Before the join,
`Body_access.designate_cells` records the targets of every cell that
intersects the range, from the least offset to the greatest offset plus the
size, or of the whole block when the offsets or the size are unbounded. A
block or state without known cells designates Top. Copied offsetmaps are
checked cell by cell, including a pointer copied without dereferencing it.
The value of each evaluated expression is also designated. The cvalue
assignment and initializer report possibly written blocks. An exact write
contributes sure bits within its transfer. A changed valuation binding, scope
binding installation (including `-eva-initialized-locals`, the return slot
and the uninitialized binding of a volatile local) or scope binding removal
only contributes a possible write. Predicate reductions contribute possible
writes as described in
[Annotation and contract reads](#annotation-and-contract-reads).

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
local binding and the loss of correlation between two guards. With
`-machdep x86_32`, a C load of a union word that covers a pointer to an
allocated block and an uninitialized word refuses as `allocated-block`;
before `designate_cells`, the same body was would-store.

**Open.** The graph merges observations at the automaton vertices. It may
connect edges that fired on different abstract paths, including at loops,
widening and late joins. Thus W_exit is an upper bound and W_sure a lower
bound even when Eva partitions the states.
The [entry producer](cache-producer.md#producer-obligations-for-exit-reuse)
takes its Exit part from the body iterator and its footprint from the
collector.
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
unsupported contract or annotation read has a Top bound.
[Annotation and contract reads](#annotation-and-contract-reads) lists the
supported observation paths. Used builtins and sweeps mark their active
recorder. Allocation targets and unknown sets are
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
The separate [production disposition](cache-producer.md#provenance-storage-and-lookup)
takes this verdict as a prerequisite and has its own counters.

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

**Open.** Child composition and replay are pending. A would-store verdict
does not establish that a body can be reused in another context.

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
`Widen.getWidenHints`, `Builtins_watchpoint.watch_hook`,
`Body_access.read_message_history`.

**Argument.** Program and AST-derived information, effective contracts,
configuration, builtin selection, static widening hints, return slots and
initial-state blocks are fixed for the observed run. ACSL evaluation observes
reads of program memory and can also refuse on a side-table access.

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
the same dispatch protocol and refuses while enabled. A message emitted once
reads the logger's history of emitted messages;
[Annotation and contract reads](#annotation-and-contract-reads) lists the
messages of ACSL clauses that refuse for that reason.

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

## Annotation and contract reads

**Claim.** On the admitted cvalue domain, the collector includes reads of
evaluated assertions, loop invariants and function-contract predicates in R,
and the targets of the values these clauses load in the designated set. This
includes alarms represented as assertions and predicates used to select
active behaviors. Evaluation without a finite read bound gives R = Top and a
clause-specific refusal. A value with unknown targets that is not loaded
refuses as `footprint-top` and leaves R unchanged. A clause whose evaluation
or transfer emits a message once refuses as `side-table` before the message.

**Kind.** OCaml obligation.

**Depends on.**
[Whole-block observations and exits](#whole-block-observations-and-exits),
[Refusal and reporting](#refusal-and-reporting) and
[Side tables and recorded joins](#side-tables-and-recorded-joins).

**Symbols.** `Transfer_logic.Make.create_from_spec`,
`Transfer_logic.Make.eval_and_reduce`, `Transfer_logic.Make.interp_annot`,
`Partition.Make.split_by_predicate`, `Cvalue_domain.State.evaluate_predicate`,
`Cvalue_domain.State.reduce_by_predicate`, `Logic_access`,
`Logic_access.load`, `Logic_access.designate`,
`Logic_access.record_reduction`, `Body_access.designate_cells`,
`Body_access.read_message_history`, `Eval_terms.find_indeterminate`,
`Eval_terms.find_logic_var`, `Eval_terms.eval_forall_predicate`,
`Eval_terms.apply_logic_builtin`, `Eval_terms.display_evaluation_error`,
`Eval_terms.eval_let_binding`, `Eval_op.find_under_approximation`,
`Eval_op.reduce_by_valid_loc`, `Eval_op.reduce_by_initialized_defined`,
`Builtins_malloc.freeable`.

**Argument.** The engine scopes recording around behavior selection,
evaluation and reduction of clauses, and ACSL predicate splits. The same
evaluator serves assertions and loop invariants, including alarm assertions
that Eva evaluates. Contract predicates use the existing label environments,
so a read in an available labeled state records the block of that state.
The global initial state used for the Init label is fixed for the analysis.
Function preconditions retain their call-site scope, including inactive
`requires` status emission. Eva does not evaluate loop variants, `decreases`
clauses, or global and type invariants; they add no read.

*Reads.* The cvalue evaluator reports actual locations before validity
narrowing. This covers scalar loads, the under-approximation query, reads of
the initializedness and dangling flags, logic-variable bindings fetched from
cvalue, and loads used while reducing a predicate. String primitives use the
existing builtin search on offsetmaps of the bases of their pointer argument.
All those bases are recorded at the wrapper boundary, even if the search
visits only a prefix of a string. Logic-variable reads can conservatively
add their synthetic blocks to the footprint. Unsupported evaluation and
unbounded load locations refuse as `annotation` or `contract`. This covers
an opaque predicate that cannot be inlined, an unavailable label and
unavailable logic operations, including `\fresh` and `\allocable`. A finite
location can still fault during evaluation. The locations evaluated before
such a failure are reported and Eva's existing error handling determines the
predicate status.

*Designations of loads.* A logic load joins the offsetmap cells of its
range into one value, with `conflate_bottom`: a pointer beside an
uninitialized cell gives an uninitialized value that designates nothing. A
location that may be invalid can also stop the evaluation at its alarm,
before the value is read: always when a predicate is evaluated, and in a
reduction without `-eva-reduce-on-logic-alarms`. `Logic_access.load`
therefore reports, before the validity test and before the join, the
location and the targets of every cell that intersects the range, as
`Body_access.designate_cells` does for C loads (see
[Whole-block observations and exits](#whole-block-observations-and-exits)).
Scalar loads of terms, logic-variable bindings, quantified tests over a
location, the under-approximation query and validity reductions use it.
String primitives report all cells of the blocks of their pointer argument.
The reduction of initializedness and dangling flags visits the raw cells
itself. The value of each evaluated term is designated as well, so the
designated set covers both the cells and the joined value.

*Unknown targets.* A designation does not load its targets: each load
reports its own location, and a load with unknown bases gives R = Top with
the clause reason. Values with unknown targets therefore refuse through the
designated set as `footprint-top`, and R stays finite. For instance, Eva
evaluates the maximum of an empty range to Top: a check on it reads nothing
and refuses as `footprint-top`.

*Allocation table.* The logic predicate `\freeable` reads the mutable
allocation table and refuses as `side-table`. On a value with unknown bases,
`Builtins_malloc.freeable` raised `Error_Top` and interrupted the analysis,
with or without the collector. It now answers Unknown. This is the only
change of analysis results in this entry: a crash becomes a completed
analysis with an unknown status.

*Emission history.* A message emitted with `~once:true` reads the logger's
history of emitted messages. `Body_access.read_message_history` refuses as
`side-table` before each such message reachable from the evaluation of terms
and predicates or from the transfer of annotations and contracts. The audit
covers every use of `once` in `plugins/eva/src/legacy/` and
`plugins/eva/src/engine/transfer_logic.ml`, and the messages of split
annotations in `Partition`.

| Message | Reachable from a body | Treatment | Evidence |
| --- | --- | --- | --- |
| `\let` binding to bottom (`Eval_terms.eval_let_binding`) | yes | side-table | execution: `let_bottom` |
| unsupported term (`Eval_terms.display_evaluation_error`) | yes, after the clause refusal | side-table | execution: `let_function` |
| range bound that cannot be evaluated (`Eval_terms.eval_term_node`) | yes, after the clause refusal | side-table | execution: `range_bound` |
| split on a predicate (`Partition.Make.split_by_predicate`) | yes | side-table | execution: `split_predicate` |
| split on an expression and partitioning parameters (`Partition.Make.fail`) | yes | side-table | execution: `split_expression` |
| false postcondition of a specification (`Transfer_logic.Make.warn_ensures_false`) | yes, at a call by the body | side-table | execution: `call_false_leaf` |
| inactive behavior at level 6 (`Transfer_logic.process_inactive_behavior`) | yes, if level 6 is shown | side-table if shown | execution: `inactive` at `-eva-verbose 6` |
| postconditions not evaluated at level 6 (`Transfer_logic.process_inactive_postconds`) | yes, if level 6 is shown | side-table if shown | source inspection |
| invalid `calls` annotation (`Transfer_logic.check_calls_annotation`) | yes, at an indirect call | side-table | source inspection |
| status of a clause (`Transfer_logic.emit_contract_status`, `Transfer_logic.emit_code_annot_status`) | yes | status join, admitted | execution: every fixture with a status |
| final status (`Eval_annots.mark_green_and_red`) | no, after the analysis | none | source inspection |
| assigns and from clauses (`Logic_inout.eval_tlval_as_zone`, `Logic_inout.check_fct_assigns`) | no | none | source inspection |

A level-6 result reads the history only when that level is shown, so the
refusal is conditional on it. A status message accompanies a status
emission that the observation records as `Statuses`. Its replay belongs to
the pending replay of that class. `Logic_inout` runs in the callwise
hooks of From and Inout, with recording suspended, or after the analysis;
Mthread, which also calls it, refuses while enabled.

The `\warning` predicate (`Eval_terms.eval_predicate`) prints a message at
each evaluation, without `once`. A replay would not print it, so the clause
refuses as `side-table` through `Logic_access.refuse_side_table` before the
message. Frama-C declares no logic builtin of that name, so no ACSL source
reaches this case: its evidence is source inspection.

*Reductions.* After a reduction, the cvalue offsetmap trees of the incoming
and outgoing states are compared, skipping the subtrees that the
hash-consed trees share. Each changed, added or removed binding contributes
a possible write to the transfer. The difference bounds writes that survive
the evaluation, including changes made by reductions of initializedness and
dangling flags. Temporary logic environments and infeasible successors have
no propagated bindings. Differences involving a whole-memory Top state
have no finite write bound and refuse. These observations supply no sure
overwrites. Opaque ACSL extensions and assembly assigns retain their
existing conservative refusals.

**Evidence.** The evaluator, reduction helpers, string-search wrapper and the
uses of `once` listed above were inspected in source. The executable
[`body-access.t`](../../../plugins/eva/tests/utils/body-access.t/run.t) uses
[`annotations.c`](../../../plugins/eva/tests/utils/body-access.t/annotations.c)
and its OCaml observer.

- Reads: behavior selection and ensures read their own globals, and the
  call-site requires global is absent. The fixture asserts the exact reads
  of an assertion, a loop invariant, an initializedness predicate, a string
  primitive, a postcondition with Old, a conjunction of `\separated`,
  `\base_addr`, `\offset`, `\block_length`, `\valid_read`,
  `\object_pointer`, `\initialized`, `\dangling` and `\is_finite`, and a set
  membership. A loop variant, a `decreases` clause, and global and type
  invariants add no read.
- RteGen: a division by zero makes the generated assertion invalid; it
  stops the propagation before the division, and the body reads only the
  divisor, through the assertion.
- Reductions: the narrowing case asserts its read and possible exit write,
  with no sure overwrite.
- Refusals: opaque predicates exercise both clause families, the delivery
  of R = Top and the statistics. `\allocable` and `\fresh` refuse with
  R = Top. The freeability case refuses as `side-table` on a static
  address; on an unknown address the analysis completes with and without
  the collector, the check is unknown and the body refuses.
- Designations: the validity case designates an allocation without loading
  it. With `-machdep x86_32`, a check on a union word that covers a pointer
  to an allocated block and an uninitialized word, and a check on the
  pointer through an address that may be null, both refuse as
  `allocated-block`. The maximum of an empty range reads nothing and
  refuses as `footprint-top`.
- Emission history: each row with execution evidence in the table above.

Each regression added for a change of this entry fails with the change
reverted: the load cases are would-store, the empty maximum gives R = Top,
the freeability case stops on `Error_Top`, and the emission cases lack the
`side-table` refusal.

**Open.** Statement contracts are filtered from ordinary statement transfer.
Eva's assembly interpretation can use their assigns clauses and continues to
refuse. This entry covers the clause evaluations that Eva actually performs.
No regression executes `\valid_function`, `\aligned`, the string primitives
other than `strlen` (`strchr`, `memchr`, `\valid_string`,
`\valid_read_string` and their wide forms), `\freeable` at a label other
than Here, `\tainted` and the taint status, or a `calls` annotation. The
messages emitted once by the evaluation of C expressions and by helpers
outside the audited files, such as the pointer comparison messages of
`Cvalue_forward` and `Cvalue_backward`, are not classified; neither is the
change of a warning category set to `once` by `-eva-warn-key`, which the
logger records when the warning is emitted. A designated range covers the
whole block when the offsets are unbounded, and every cell from the least
to the greatest offset when they are strided, such as a field read across
the elements of an array. Either can refuse a body that loads only part of
a block holding an allocation address. The cost of
`designate_cells` at each C scalar load is not measured. Safety and Reach
replay are pending.
