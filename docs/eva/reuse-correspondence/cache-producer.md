# Entries from fresh bodies

## Key and footprint from the collector

**Claim.** A completed body observation yields a candidate only for a
product consisting of cvalue alone. An accepted observation provides the
four sets of the candidate's footprint. The key contains
R ∪ (W_exit ∖ W_sure), with variable-validity blocks of W_exit retained.
It is closed under `relate` in the producing input and is at most
`-eva-cache-key-limit` blocks. The option defaults to 256 and permits zero.

**Kind.** OCaml obligation.

**Depends on.** [Whole-block observations and exits](body-access.md#whole-block-observations-and-exits),
[entry construction](entry.md#sound-entry-from-producer-soundness-and-coverage),
and [`relate` empty for cvalue](reuse-operation.md#relate-empty-for-cvalue).

**Symbols.** `Cache_producer.Make.store`, `Cache_producer.footprint`,
`Cache_producer.key_seed`, `Cache_producer.close_key`, and
`Cache_entry.Make.make`.

**Argument (source inspection).** The typed check of the active domain
structure permits the single cvalue leaf. The producer consumes the
collector verdict unchanged. It copies the finite collector sets and
checks W_sure ⊆ W_exit ⊆ W. It uses the same return-slot convention as
supplied entries. The matching seed includes every reported read, even a
read after a full overwrite. Of the other blocks it includes the possible
exit writes that are absent from W_sure and the exit writes whose base has
variable validity. Each closure step checks the current size, refuses a
Top result of `relate`, or adds the related blocks and iterates until there
is no addition. Every recursive step strictly increases the key. Cvalue
has an empty relation, so it reaches the fixpoint on the seed.
`Cache_entry.Make.make` checks the inclusion and closure and projects the
producing input to the closed key.

**Evidence (executed).** [`cache-producer.t`](../../../plugins/eva/tests/utils/cache-producer.t/run.t)
asserts the sets of the entry for `leaf`, including the CIL temporary read
by the return, checks the filtered input values, and checks that a full
overwrite of `out` leaves it out of the key. The partial array write needs
`pair` in the key even though the body reads no block. The two-block input
refuses at limit one and stores at limit two. Cvalue with sign refuses as
`product`.

**Open.** The closure growth and Top cases cannot be observed with the
current relation. The existing refusal on allocated blocks normally
prevents any variable-validity block from reaching key construction.
The key inclusion is checked on the collected sets. Establishing the
concrete coverage hypotheses is a separate obligation below.

## Producer obligations for exit reuse

**Claim.** A produced entry holds the fresh body's exit states, projected
to the key and W, with each original partition key. Its input and exits are
maps. Every stored exit binds every block of the overlay W_exit, including
the return block. An observed body can supply an empty exit list.

**Kind.** OCaml obligation.

**Depends on.** [The written sets of a supplied entry and its key](reuse-operation.md#the-written-sets-of-a-supplied-entry-and-its-key),
[the cvalue reuse law](reuse-operation.md#reuse-sound-for-cvalue) and
[entry construction](entry.md#sound-entry-from-producer-soundness-and-coverage).

**Symbols.** `Compute_functions.Make.compute_and_cache_call`,
`Iterator.Make.compute`, `Cache_producer.produce`,
`Cache_producer.has_preconditions`, `Cache_entry.Make.make`, and
`Supplied_entries.supply_produced`.

**Argument (source inspection).** The body iterator returns the expanded
store at the return vertex. Its caller offers the input captured before
the body and the resulting states before the call's outer cleanup. The
producer checks each exit map for every block it would overlay. Projection
to K ∪ W preserves those bindings by W_exit ⊆ W. An absent binding cannot
be replayed through cvalue's merge, even if the absence comes from leaving
an inner scope. This check is stricter than the hand-supplied API's check:
that API allows a known inner local to be absent because the caller should
have no binding for it. The producer snapshots each holder cell, which
Eva otherwise mutates as it goes on analysing the caller. The reuse
fixture changes only the identifier when it supplies an entry.

| Obligation from `Supplied_entries.supply` | Evidence for a produced entry |
| --- | --- |
| R covers every read, including a load through a pointer. | The collector's evaluator, scalar and aggregate read hooks report the accessed bases. Designation of a pointer target alone checks for an allocated block and does not add a read. See [body access](body-access.md#whole-block-observations-and-exits). Coverage for every concrete execution of an admitted Eva body is open. |
| W and W_exit cover writes, including writes that leave their input value. | The collector observes transfers, so a write does not depend on comparing input and output maps. Scope updates and narrowing count as possible writes. Its backward graph traversal includes all observed returning paths and can include extra writes. The argument from observed transfers to coverage of all concrete executions remains open. |
| W_sure is a lower bound on full overwrites on all paths to an exit. | The collector intersects sure bits at joins and retains a base only when the bits cover its full known range at the return. Scope updates and narrowing do not count as sure writes. The return slot follows the existing entry convention and must be present in every stored exit. The connection from the graph lower bound to concrete overwrites, including at offsets, remains open. |
| The key includes R ∪ (W_exit ∖ W_sure) and is closed. | Established by key construction and the constructor checks described above. |
| The body does not allocate, free, or end the lifetime of a block outside its locals. | The producer refuses every refusal issued by the collector. Allocation, release, builtins, sweeps, allocated bases, recursive bodies and nested calls are among the paths refused by the collector. This uses the collector's instrumented effect coverage. The transitive side-table and allocation audit remains open. |
| Every returning execution is covered by an exit, including changes to holders caused by leaving an inner scope. | The iterator supplies the producing Exit states, and the producer refuses an observed sweep or any missing overlay binding. Callee preconditions are excluded from the collector, and the current fixture hit checks their statuses without consuming their reduced states. The producer therefore refuses when requires clauses would be checked. Exit soundness relative to the concrete semantics and replay of inner-scope sweeps remain open. |

On a hit, Eva still runs the outer cleanup in `Transfer_stmt.do_one_call`.
`Cvalue_domain.State.leave_scope` uses the post-state holder set to sweep
the callee's departing locals and formals. `finalize_call` then accumulates
the post-state's holders into the caller's holder set. This preserves the
caller's holder information after that step. Agreement on what the earlier
sweep should see in an arbitrary caller frame remains open.

**Evidence (executed).** [`cache-producer.t`](../../../plugins/eva/tests/utils/cache-producer.t/run.t)
supplies the first fresh `leaf` entry explicitly to a fixture analysis.
The second call uses that entry with a different value of `keep`, confirms
the hit, and compares the whole caller model with the fresh result. A scope
removal that the collector accepts refuses as `exit-binding`. A scope
with a collector sweep retains the `sweep` refusal. An otherwise accepted
body with a callee precondition refuses as `preconditions`.

**Open.** A projected match only gives agreement on key contents. The
same stored witness must agree on the liveness of written blocks and
allocator state, with common program and entry bindings. The producer
does not supply this witness, including for contexts that may differ
outside the key. Cvalue map checks also do not prove nonempty
concretisation. Links and checked counterexamples are in
[entry construction](entry.md#sound-entry-from-producer-soundness-and-coverage).

## Provenance, storage and lookup

**Claim.** Each completed body observation leads to one production
disposition and count. The stored entry carries the Exit part, the
collector's recorded join classes, the used function with its body call
mode, and an Inner reference if statement states were recorded. Memexec
still serves ordinary calls. Only explicit fixture supply can make a
produced entry a lookup candidate.

**Kind.** OCaml obligation.

**Depends on.** [Refusal and reporting](body-access.md#refusal-and-reporting)
and [No analysis has both caches](reuse-operation.md#no-analysis-has-both-caches).

**Symbols.** `Call_cache.Make.store`, `Call_cache.Make.lookup`,
`Cache_producer.entries`, `Cache_producer.Table`, `Cache_producer.recorded`,
`Cache_producer.inner`, `Cache_producer.used_functions`,
`Supplied_entries.supply_produced`, and the `Statistics.cache_produced`
and `Statistics.cache_production_refused` counters.

**Argument (source inspection).** Only a fresh, completed body with an
observation reaches production. Production runs with recording suspended
so it contributes no accesses to the enclosing body's observation. The
producer takes no part in either lookup. Its store follows the current
project and analysis, is cleared when results are invalidated or a new
analysis starts, and is not marshalled. Disabling memexec does not disable
production, so runs with all calls analysed can measure admission.
Disabling the collector removes the observation and therefore the
production step. The statistics count production even when its message
category is off. With `-eva-msg-key cache,cache-producer`, a completed
observation extends the call's disposition with the producer result.

The admitted collector family contains no nested call, so the only used
function is the subject and the only mode in a produced entry is body.
The Inner reference names the saved statement states by the producing
callstack. The collector supplies the classes of the observed joins. The
data for per-position Safety and Reach joins belongs to their producer and
replay work, in [#47](https://github.com/nyandrianinamamy/frama-c/issues/47)
and [#48](https://github.com/nyandrianinamamy/frama-c/issues/48).

**Evidence (executed).** [`cache-producer.t`](../../../plugins/eva/tests/utils/cache-producer.t/run.t)
asserts the used function and its mode, the Inner reference, and the States
join class. The ordinary run uses a memexec hit on the second call.
In the replay run, the fixture supplies the first fresh entry and records
two hits, with zero fresh entries for that body in the replay analysis.
[`statistics.t`](../../../plugins/eva/tests/utils/statistics.t/run.t)
checks the new storage counts alongside the existing counts.
[`dev/collector-counts.sh`](../../../dev/collector-counts.sh) aggregates
both sets of counts over the Eva test configurations.

**Open.** The stored join classes do not establish the Safety and Reach
coverage or replay claims. Inner reconstruction and serialization remain
open. The limit controls key cardinality, independently of retention of
the projected exit states and the number of entries.
