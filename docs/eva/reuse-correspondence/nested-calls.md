# Nested call collection

## Composition along the observed path

**Claim.** The enclosing observation covers the accesses reported by the
call transfer, including the selected child body or the footprint of the
winning supplied entry. It carries the observed designations, recorded
join classes, used functions and refusals. The produced entry retains
references to the entries used at the nested call sites.

**Kind.** OCaml obligation.

**Depends on.** [Body access observations](body-access.md#whole-block-observations-and-exits),
[Entry coverage](entry.md#sound-entry-from-producer-soundness-and-coverage),
[Shared Inner](inner.md#coverage-of-matching-visits-on-the-key) and
[Hit soundness](hit.md#hit-soundness).

**Symbols.** `Transfer_stmt.Make.do_one_call`,
`Compute_functions.Make.compute_and_cache_call`,
`Body_access.include_fresh`, `Body_access.include_hit`,
`Body_access.at_call_site`, `Body_access.add_exit_write`,
`Cache_entry.Cvalue.reference`, `Cache_producer.produce` and
`Supplied_entries.Lookup.find`.

**Argument (source inspection).** The caller records evaluation of actuals,
binding of formals, requires checks, any reduction of the actuals, cleanup
and assignment of the result. A fresh body has its own recorder. On
completion, the caller joins its R, W, designations, metadata owners and
recorded join classes, and takes every refusal the child reported. The
callee retains its usual allocation checks during its requires clauses.
For other observations those clauses use the caller's recorder.

On a supplied hit, R and W come from the winning entry, including work
before a fault or on a nonreturning path. The entry's observation supplies
the recorded join classes and designations. Its collector dependencies
supply the transitive used functions. The actual call transfer provides the context, including the
current call site, its arguments, scope cleanup and return assignment. The
key of the winning entry bounds the values consumed by lookup and replay.
Lookup and reconstruction run with recording suspended. No rejected
candidate contributes accesses, effects, dependencies, refusals or a child
reference. A hand-supplied entry with no producing observation and a
memexec hit each refuse the enclosing body as `nested-call`. For a
memexec hit, the bound is Top since the collector has no required footprint
from that cache. Its producing trace still contributes used functions and
recursion information.

W is the union of prefix writes, including paths with no successor. A
returning child contributes its W_exit and the full bit ranges of known
validity blocks in its W_sure. The caller independently records each
resolved call target and then each returned state during cleanup, actual
reduction and result assignment. A branch starts with an empty local
write summary. Continuing branches join possible writes and intersect
sure bits. The writes before the split are then composed with that
result. Prefix coverage also retains the writes of stopped branches.
The same join applies across input partitions and later visits of an
automaton edge. The backward walk from the exit bounds the possible
returning writes. In the forward analysis, the zero-iteration path and
all observed back edges participate in the must-write intersections.

**Lifetime obligation (source inspection).** The caller must retain
surviving holder updates even though it omits expired child blocks from
its overlay. Formals are installed by the actual bindings. The child's
return slot lasts through the caller's result assignment. Child formals,
automatic locals and the return slot contribute to R and W when
accessed. They have left scope by the end of the call transfer. Their
bindings are never restored by an enclosing overlay. This omits only
the ephemeral blocks themselves. Any rewrite of a surviving
holder is a separate effect. A child's lexical sweep is foreign to
the enclosing unit, even when admitted for the child. Both fresh and
supplied children with that sweep refuse the enclosing body. The fresh
and supplied call paths both execute outer cleanup. Escaped child
addresses remain subject to the sweep and allocation refusals.

Lean's `Coverage.exitWrites` counts every write event on a returning
execution, including writes to blocks that later leave scope. Applying
it to Eva's surviving exit writes needs a lifetime-aware statement.

A completed nested fresh body contributes its observation even if its
producer does not create an entry. The produced enclosing entry has a
strong reference at the current statement to each fresh entry produced
and each supplied entry selected. The referenced entry owns its child
references. A body with no entry of its own contributes inline along with
its child references. Those references retain the path of statements
through the inlined body. The enclosing record carries the transitive
used functions and modes on both paths. A fresh child or a supplied
child that consults widening hints makes the enclosing observation
depend on its own entry-time generation. A change during that enclosing
analysis refuses the observation. A supplied child with a stale stamp
fails admission before its effects can be included.

The empty automatic-allocation lookup during call finalization makes no
memory change. A nonempty result executes the deallocation and retains
its refusals. Admission to an enclosing hit with a nested function
definition requires the current project's automatic-allocation registry
to have no automatic blocks. This conservative check makes each skipped
cleanup empty even when the callstack or registry has changed since
production. Admission also rejects if the cached body or one of its used
functions is already active in the caller. The same lookup uses #44's
sweep, hint and watchpoint checks and the comparison of the warning
categories (`warn-categories`), after the rejections of every candidate
(`product`, `consumer`, `stop-at-nth-alarm`, `callback`) of
[Safety at a hit](safety.md#a-hit-runs-no-client-that-is-not-audited).
For matching entries that pass those checks, lookup inspects the subject's
AST for direct and indirect call instructions, including calls in local
initializers. `supply_produced` takes any produced entry; `supply` refuses
an entry for a body that may call a function with a body before any lookup,
and supplies the others. The presence of a call gives `nested-delivery`
regardless of child references or the observed call trace. Direct
`Frama_C_show_each*` and `Frama_C_domain_show_each*` calls are leaf
displays, which hand-supplied fixtures use to show whether the body ran.
Eva's collector still refuses to produce entries that execute those
directives, and dump directives remain subject to the call check.

**Evidence (executed).**
[`nested-access.t`](../../../plugins/eva/tests/utils/nested-access.t/run.t)
asserts the enclosing observation before its verdict, checks the referenced
entry by identity, exercises a rejected candidate followed by a hit, and
checks deallocation refusal propagation from a fresh child. It checks
prefix coverage for a child with no exit, preserves a reference through an
intermediate body with preconditions, and exercises matching enclosing
entries rejected for automatic cleanup and for a child on the active
callstack. The split-return fixtures assert the key and sure writes with
fresh and supplied children and with two calls in one main. They compare
the result and a division alarm with caching disabled. The delivery fixture
supplies the same key, footprint, input and exits through each
constructor. The produced constructor is tried for a referenced child, an
inline body with a precondition and an inline specification, and the
hand constructor for the inline specification:
`Supplied_entries.supply` refuses, before any lookup, a hand entry for a
body that may call a function with a body
([The passes after the analysis](safety.md#the-passes-after-the-analysis-draw-no-conclusion-where-a-hit-reached-no-point)).
Each candidate tried gives `nested-delivery`. The assertion status matches
caching disabled in all three cases. The supplied-child criterion is
exercised by the child's confirmed hit and the enclosing observation. No
enclosing hit is admitted.
The transitive test exercises a produced middle entry at the same
composition function used by a supplied hit, then performs three real
analyses. The temporary guard rejects that middle entry in the second
analysis. The third finds the grandchild active and rejects the enclosing
entry as `recursion`.

**Open.** The fresh collector bounds are conditional on coverage of the
child, including before faults. The hit bounds also require an admitted
entry whose footprint covers the skipped execution under its call context.
The argument for the Eva match witness and full correspondence with the
whole-block model remains open. See [Hit soundness](hit.md#hit-soundness).
Recorded classes alone cannot deliver per-position contributions.
Before enabling an enclosing hit, the Safety part of the enclosing body
must hold the writes of each child at its relative call site, including
those of children analysed afresh and of inline work, and a hit must mark
every function whose body visits it skips, transitively. The part recorded
today holds only the writes that the hits of its calls deliver, and
`Safety_delivery.skip_visits` marks the called function alone
([Safety at a hit](safety.md#the-safety-part-records-the-writes-of-the-body)).
End-of-analysis processing must suppress conclusions requiring complete
visit information for those functions. The Reach part recorded today has
the same limit
([Reach at a hit](reach.md#the-reach-part-records-the-reach-of-the-body)),
and #51 owes the remaining position-specific contributions for that same
nested work.

## Dependencies on entry values

**Claim.** For supported cvalue calls the collector keeps the read
footprint independently of the entry dependencies. If every path to the
call entry overwrites an entire block, a dependency reported by the child
on that block need not be a dependency on its value at the caller's entry.

**Kind.** Argued, not modelled. The argument is conditional on the
transfer observations.

**Argument (source inspection).** For each call edge the recorder adds the
child's input dependencies at the source vertex. A fresh call uses the
child's observed dependencies. A supplied hit uses its matching key, which
can contain additional blocks. Both keep the child's read footprint.
Call-local blocks used while binding arguments and removing locals are
provided by the call rather than by the caller's input. Reads of the actual
arguments themselves remain caller dependencies.

The forward must analysis starts at the entry with no overwritten bits.
For each successful transfer it adds the bits that all observations of
that edge surely wrote, and intersects incoming bits at each join. The bits
computed at the source of the call therefore under-approximate the bits
overwritten before any visit to it. The collector removes a child
dependency there only when the entire known validity range is in those
bits. It makes no deduction from writes on the call edge itself. The
call dependency is recorded even if the transfer fails to return. Missing
prefix facts retain the dependency. Direct reads and reads from inlined
contracts stay conservative. The producer adds possible surviving exit
writes outside W_sure, then applies its existing validity, closure and
size checks.

In `x = 0; g();`, a read of `x` by `g` depends on the value from the
assignment in every execution reaching the call. Matching two caller
inputs on other dependencies suffices to replay the assignment and then
agree on `x` at this use, provided the access is valid and there is no
intervening effect that depends on the incoming value. Our transfer
composition gives precisely this prefix ordering. The ordinary write
liveness, allocation, side-table and domain premises still apply.

**Evidence (executed).** The same fixture checks that `outer` reads
`payload,x` with key `{payload}` for both a fresh call and a hit. An
optional preceding overwrite keeps `x` in the dependencies. A contract
that reads a callee formal keeps its read in the footprint while the
dependency on its value comes from the actual argument.

**Open for a Lean ticket.** Neither `CacheEntry.sound_of_producer`
nor `CacheEntry.shared_inner` has a premise for the reduced key.
Both use the prefix replay argument of `Entry.lean` with `KeyCovers`,
which requires R ⊆ K. A replacement premise would require that every
read outside K, on every covered finite prefix, follows a full overwrite
of that block on the same prefix. It must also account for entry agreement,
liveness, allocation, scope and any intervening effects that can change
the value. An inductive replay argument would derive agreement at the
read from the earlier matched transitions, even when the execution
never reaches an exit. It would still need the key condition for
possible surviving writes outside W_sure. Relational closure of a
child's dependencies is open beyond cvalue.

## Inline specifications and builtins

**Kind.** OCaml obligation.

**Symbols.** `Transfer_specification.precise_loc_of_assign`,
`Transfer_specification.Make.compute_effects`,
`Transfer_specification.Make.check_post_assigns`,
`Cvalue_domain.State.logic_assign` and
`Compute_functions.Make.compute_call_with_target`.

**Argument (source inspection).** For specifications Eva observes
behavior selection and predicate evaluations, the location evaluation for
assigns and from clauses, and the blocks read by from clauses. Address-only
dependencies designate blocks. A weak assigns update contributes a
possible write, including when the resulting binding is unchanged. The
subsequent garbled-mix check reads the assigned location. The observed
clauses and effects are inline. Unbounded or uninterpretable assigns and
from clauses still refuse. Specification generation without explicit
default assigns and ordered warning histories still refuse, including the
specification announcement when its verbosity is enabled. Explicit
allocation and frees clauses refuse as allocation or deallocation when
selected. Eva's unbounded allocation clause performs no transfer.
An explicit allocation clause, including an empty clause or one on an
inactive behavior, can consult the message history. The logger reports
the consultation at the diagnostic under #44's per-event and category
policies. Behavior effects begin from alternatives of the same input.
Shared assigns and predicate reductions report possible writes only.
The memoized interpretation of a behavior contributes its possible
writes on its first execution, including writes discarded by a later
postcondition or narrowing. Specification result initialization affects
only the private return slot.

Registered cvalue builtins run inline with a Top memory bound and a
builtin refusal. Their executed specification and instrumented effects
can add more specific reasons. Allocation builtins report their effects
independently of assigns. Special show and dump directives report Top
reads and dependencies because state printers may inspect bindings
directly. Their refusal is `builtin` or `dump`, respectively.

**Evidence (executed).** The bounded specification fixture asserts the
selector, from and post-assigns reads, the destination write and the
status join under `-eva-verbose 2`. The live deallocation fixture
exercises the actual free builtin and its enclosing refusal. The explicit
empty-allocation and full state dump fixtures check the pre-verdict
`side-table` refusal and Top read bound, respectively.
