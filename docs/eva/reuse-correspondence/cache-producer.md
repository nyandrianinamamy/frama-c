# Entries from fresh bodies

## Key and footprint from the collector

**Claim.** A completed body observation yields a candidate only for a
product consisting of cvalue alone. An accepted observation provides the
four sets of the candidate's footprint. The key contains the dependencies
on the values at entry and W_exit ∖ W_sure. It retains variable-validity
blocks of W_exit.
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
supplied entries. The matching seed uses the collector dependencies.
Direct reads remain dependencies even after a full overwrite. Some reads
from nested calls depend on the result of an earlier write in the caller.
See [Dependencies on entry values](nested-calls.md#dependencies-on-entry-values).
The seed also includes exit writes absent from W_sure and exit writes whose
base has variable validity. Each closure step checks the current size, refuses a
Top result of `relate`, or adds the related blocks and iterates until there
is no addition. Every recursive step strictly increases the key. Cvalue
has an empty relation, so it reaches the fixpoint on the seed.
`Cache_entry.Make.make` checks the inclusion and closure and projects the
producing input to the closed key.

A callee's block can occur in R and therefore in the key. For example,
the CIL return temporary is in the test's key because the body reads it.
This qualifies the parent spec's wording on body locals.
[`Transfer_stmt`](../../../plugins/eva/src/engine/transfer_stmt.ml)
binds the arguments in `Domain.start_call` before the lookup runs.
[`Cache_entry.Make.check`](../../../plugins/eva/src/engine/cache_entry.ml)
compares the projected maps. A formal in the key matches on its entry
value. A body local that is absent until the body starts matches by its
absence from both maps.

**Evidence (executed).** [`cache-producer.t`](../../../plugins/eva/tests/utils/cache-producer.t/run.t)
asserts the sets of the entry for `leaf`, including the CIL temporary read
by the return, checks the filtered input values, and checks that a full
overwrite of `out` leaves it out of the key. The partial array write needs
`pair` in the key even though the body reads no block. The two-block input
refuses at limit one and stores at limit two. Cvalue with sign refuses as
`product`.

**Open.** Cvalue's relation allows no closure growth. The existing
refusal on allocated blocks normally
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
[entry construction](entry.md#sound-entry-from-producer-soundness-and-coverage)
and [hit soundness](hit.md#hit-soundness).

**Symbols.** `Compute_functions.Make.compute_and_cache_call`,
`Iterator.Make.compute`, `Cache_producer.produce`,
`Cache_producer.has_preconditions`, `Cache_entry.Make.make`, and
`Supplied_entries.supply_produced`.

**Argument (source inspection).** The body iterator returns the expanded
store at the return vertex. Its caller offers the input captured before
the body and the resulting states before the call's outer cleanup. The
producer checks each exit map for every block it would overlay. Projection
to K ∪ W preserves those bindings by W_exit ⊆ W. Cvalue merge cannot replay a deletion. A recorded lexical sweep target may
be absent if it was absent at entry. The producer adds the target to the
key and the supplied lookup checks the current input for absent sweep
targets and potential holders of their addresses.
[Lexical sweep in cvalue](collector-effects.md#lexical-sweep-in-cvalue). The producer snapshots each holder cell, which
Eva otherwise mutates as it goes on analysing the caller. The reuse
fixture changes only the identifier when it supplies an entry.

| Obligation from `Supplied_entries.supply` | Evidence for a produced entry |
| --- | --- |
| R covers every read, including a load through a pointer. | The collector's evaluator, scalar and aggregate read hooks report the accessed bases. Designation of a pointer target alone checks for an allocated block and does not add a read. See [body access](body-access.md#whole-block-observations-and-exits). Coverage for every concrete execution of an admitted Eva body is open. |
| W and W_exit cover writes, including writes that leave their input value. | The collector observes transfers, so a write does not depend on comparing input and output maps. Scope updates and narrowing count as possible writes. Its backward graph traversal includes all observed returning paths and can include extra writes. The argument from observed transfers to coverage of all concrete executions remains open. |
| W_sure is a lower bound on full overwrites on all paths to an exit. | The collector intersects sure bits at joins and retains a base only when the bits cover its full known range at the return. Scope updates and narrowing do not count as sure writes. The return slot follows the existing entry convention and must be present in every stored exit. The connection from the graph lower bound to concrete overwrites, including at offsets, remains open. |
| The key includes the entry dependencies, sweeps and W_exit ∖ W_sure and is closed. | Established by key construction and the constructor checks described above. |
| The body does not allocate, free, or end the lifetime of a block outside its locals. | The producer refuses every refusal issued by the collector. Allocation, release, unsupported builtins, foreign sweeps, allocated bases and recursive bodies are refused, including on nested paths. This uses the collector's instrumented effect coverage. The transitive side-table and allocation audit remains open. |
| Every returning execution is covered by an exit, including changes to holders caused by leaving an inner scope. | The iterator supplies the producing Exit states. The producer permits only checked lexical sweeps and refuses missing overlay bindings except for their absent targets. Callee preconditions are excluded from the collector, and the current fixture hit checks their statuses without consuming their reduced states. The producer therefore refuses when requires clauses would be checked. Exit soundness relative to the concrete semantics and replay of inner-scope sweeps remain open. |

On a hit, Eva still runs the outer cleanup in `Transfer_stmt.do_one_call`.
`Cvalue_domain.State.leave_scope` uses the post-state holder set to sweep
the callee's departing locals and formals. `finalize_call` then accumulates
the post-state's holders into the caller's holder set. This preserves the
caller's holder information after that step. The earlier sweep still
owes a separate argument for a holder known only to the current caller.
The later accumulation comes after the sweep and cannot establish that
the earlier step saw that holder. Skipped inner scopes have their own
open admission condition. [Admission condition for sweeps of own locals](frame.md#admission-condition-for-sweeps-of-own-locals).

**Evidence (executed).** [`cache-producer.t`](../../../plugins/eva/tests/utils/cache-producer.t/run.t)
supplies the first fresh `leaf` entry explicitly to a fixture analysis.
The second call uses that entry with a different value of `keep`, confirms
the hit, and compares the whole caller model with the fresh result.
A scope removal without a recorded sweep still refuses as `exit-binding`.
The own-local sweep fixture records and admits a lexical sweep. An otherwise
accepted body with a callee precondition refuses as `preconditions`.

**Open.** The projected theorem takes `ReplayCompatible` as a lookup
premise. For every current memory covered by an admitted match, Eva must
justify a single stored witness agreeing on key contents, liveness of
written blocks, and allocator state, with common program and entry
bindings. The generic proof composes this witness, which the value-domain
instance constructs. The cvalue lookup owes the construction. The
producer's map checks leave nonemptiness of the stored concretisation open. The proof and checked counterexamples are in
[hit soundness](hit.md#hit-soundness).

## Refusals at admission

[`cache-producer.t`](../../../plugins/eva/tests/utils/cache-producer.t/run.t)
calls `Cache_producer.Make.store` on constructed observations and call
results. It checks the specific refusal and verifies that no entry was
stored.

| Refusal | Input or invariant |
| --- | --- |
| `footprint-top` | A Top read set with an accepting verdict. The test isolates the producer from collector refusals. A predicate split that narrows a binding, for example, can make the write set Top and is refused by the collector as `annotation`. |
| `invalid-footprint` | A sure-written block missing from the exit-write set. |
| `not-cacheable` | A result marked `NoCacheCallers` with an accepting verdict. The iterator propagates this flag from a call, which also records a collector refusal through `Transfer_stmt.call`. |
| `input-state` | A Top input and a map exit. |
| `exit-state` | A map input and an explicit Bottom exit state. The empty exit list is allowed. |
| `relate-top` | Defensive. [`Cvalue_domain.State.relate`](../../../plugins/eva/src/domains/cvalue/cvalue_domain.ml) returns `Base.SetLattice.empty` for every input, and the producer admits only cvalue. |

## Provenance, storage and lookup

**Claim.** Each completed body observation leads to one production
disposition and count. The stored entry carries the Exit part, the
collector's recorded join classes, used functions with their call modes,
sweep targets, the stamp of a widening read, and an Inner reference if cvalue statement states were recorded. Memexec
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

The entry carries transitive used functions and modes, references to
entries at the call sites that used them, and classes of recorded joins.
See [Nested call composition](nested-calls.md#composition-along-the-observed-path).
The producer gives an Inner reference when the body saves statement
states and the cvalue store records them. The reference names the producing
callstack. [`Engine.Store.register_state`](../../../plugins/eva/src/engine/engine.ml)
joins repeated visits at the same control point and callstack, so the
query can include states from other calls. The collector supplies the
classes of the observed joins. The
[Shared Inner record](inner.md#saved-states-and-the-public-query) states the
coverage premise for this reference. Per-position Safety and Reach data
belongs to the producer and replay work in [#47](https://github.com/nyandrianinamamy/frama-c/issues/47)
and [#48](https://github.com/nyandrianinamamy/frama-c/issues/48).

**Evidence (executed).** [`cache-producer.t`](../../../plugins/eva/tests/utils/cache-producer.t/run.t)
asserts the used function and its mode and the States join class. It
queries the cvalue state at the Inner callstack, checks that disabling
recording for the callee or cvalue omits the reference, and shows two
visits to one callstack where the first entry has input `g = {1}` and the
Inner query returns `g = {1; 2}`. The ordinary run uses a memexec hit on
the second call.
In the replay run, the fixture supplies the first fresh entry and records
two hits, with zero fresh entries for that body in the replay analysis.
[`statistics.t`](../../../plugins/eva/tests/utils/statistics.t/run.t)
checks the new storage counts alongside the existing counts.
[`dev/collector-counts.sh`](../../../dev/collector-counts.sh) aggregates
both sets of counts over the Eva test configurations. These are counts
of the first disposition per observed body under each test's own memexec
setting. A memexec hit skips the body and produces no observation. The
producer checks `product` before the collector verdict, so that refusal
masks collector causes for an unsupported product.

**Open.** The stored join classes do not establish the Safety and Reach
coverage or replay claims. Inner reconstruction and serialization remain
open. The limit controls key cardinality, independently of retention of
the projected exit states and the number of entries.
