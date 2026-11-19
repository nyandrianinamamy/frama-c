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
before a fault or on a nonreturning path. The entry's producing observation
supplies the recorded join classes, designations and transitive used
functions. The actual call transfer provides the context, including the
current call site, its arguments, scope cleanup and return assignment. The
key of the winning entry bounds the values consumed by lookup and replay.
Lookup and reconstruction run with recording suspended. No rejected
candidate contributes accesses, effects, dependencies, refusals or a child
reference. A hand-supplied entry with no producing observation and a
memexec hit each refuse the enclosing body as `nested-call`. For a
memexec hit, the bound is Top since the collector has no required footprint
from that cache. Tests can still use either kind of hit at the call seam.

W is the union of prefix writes, even when the call has no successor. On a
returning call the current edge gets the child's W_exit and the full bit
ranges of known-validity blocks in its W_sure. The edge keeps contributions
from the actual call transfer too. The caller's normal backward walk and
forward must analysis account for branching and repeated executions of
the edge. The call-local formals, automatic locals and return slot remain
in R and W when accessed. They are removed from the enclosing body's
transfer of exit writes and sure writes because the call ends their
lifetimes. This exit bound is on surviving writes. Lean's
`Coverage.exitWrites` ranges over every write event on a returning
execution, including writes to blocks that later leave scope. Applying
that premise to the raw Eva exit set would need a separate account of
call-local lifetimes. The fresh and supplied call paths both execute the
outer cleanup. A scope sweep still refuses if Eva's existing sweep path
runs, including when it is the cleanup of a nested body.

A completed nested fresh body contributes its observation even if its
producer does not create an entry. The produced enclosing entry has a
strong reference at the current statement to each fresh entry produced
and each supplied entry selected. The referenced entry owns its child
references. Calls with no child entry contribute inline, and the enclosing
record carries the transitive used functions and modes on both paths.

The empty automatic-allocation lookup during call finalization makes no
memory change. A nonempty result executes the deallocation and retains
its refusals. Admission to an enclosing hit with a nested function
definition requires the current project's automatic-allocation registry
to have no automatic blocks. This conservative check makes each skipped
cleanup empty even when the callstack or registry has changed since
production. Admission also rejects if the cached body or one of its used
functions is already active in the caller.

**Evidence (executed).**
[`nested-access.t`](../../../plugins/eva/tests/utils/nested-access.t/run.t)
asserts the enclosing observation before its verdict, checks the referenced
entry by identity, exercises a rejected candidate followed by a hit, and
checks deallocation refusal propagation from a fresh child. It checks
prefix coverage for a child with no exit and also
exercises a matching enclosing entry rejected for automatic cleanup and
one rejected for a child on the active callstack.

**Open.** The fresh collector bounds are conditional on coverage of the
child, including before faults. The hit bounds also require an admitted
entry whose footprint covers the skipped execution under its call context.
The argument for the Eva match witness and full correspondence with the
whole-block model remains open. See [Hit soundness](hit.md#hit-soundness).
Recorded classes alone do not replay per-position contributions. After
Safety and Reach delivery, a hit of an enclosing entry must mark every
function whose visits it skips, including transitive children and body
work recorded inline, before end-of-analysis processing. That processing
must suppress conclusions requiring complete visit information for all
such functions.

## Dependencies on entry values

**Claim.** For supported cvalue calls the collector keeps the read
footprint independently of the entry dependencies. If every path to the
call entry overwrites an entire block, a dependency reported by the child
on that block need not be a dependency on its value at the caller's entry.

**Kind.** Argued in prose, conditional on the transfer observations.

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

**Open.** The Lean proof currently uses `KeyCovers` with R ⊆ K. It does
not directly establish the reduced-key claim for an implementation that
keeps R and the entry dependencies separately. The prose argument gives
the change required of the replay premise. It uses agreement on reads
at their program points, derived from agreement at entry and replay of
preceding writes. Relational closure of a child's dependencies is open
beyond cvalue.

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

Builtins likewise run inline. Their specification evaluation and any
instrumented operations contribute at the call site. An unaudited builtin
still refuses with unknown accesses. The actual allocation builtins
supply the refusal reasons for their effects, independently of assigns.

**Evidence (executed).** The bounded specification fixture asserts the
selector, from and post-assigns reads, the destination write and the
status join under `-eva-verbose 2`. The live deallocation fixture
exercises the actual free builtin and its enclosing refusal.
