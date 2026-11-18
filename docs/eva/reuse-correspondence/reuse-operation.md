# Reuse operation

Claims about the cache entry and the reuse operation added by
[issue #45](https://github.com/nyandrianinamamy/frama-c/issues/45), and about
the laws of `filter`, `relate` and `reuse` for the cvalue domain that a hit
relies on. In this version, only entries supplied by a test module reach the
reuse operation.

The modules are
[`plugins/eva/src/engine/cache_entry.ml`](../../../plugins/eva/src/engine/cache_entry.ml)
(the entry and the reuse operation, for any domain with `filter`, `relate` and
`reuse`) and
[`plugins/eva/src/engine/supplied_entries.ml`](../../../plugins/eva/src/engine/supplied_entries.ml)
(the entries supplied with cvalue states, and their lookup on the product of
the engine). The seam
([`call_cache.ml`](../../../plugins/eva/src/engine/call_cache.ml), see
[Call-cache seam](call-cache-seam.md)) consults them.

The regression named in several entries is the ptests fixture
[`plugins/eva/tests/value/cache_supplied.c`](../../../plugins/eva/tests/value/cache_supplied.c)
with its test module
[`cache_supplied.ml`](../../../plugins/eva/tests/value/cache_supplied.ml),
which supplies the entries, runs the analysis, then prints the entries and the
counts. It has four runs, with the message category `cache` enabled: run 0 in
the default configuration with Eva alone; run 1 with
`-eva-domains cvalue,sign`; run 2 with `-eva-no-memexec`; run 3 with the Inout
plug-in loaded. Their oracles are
`plugins/eva/tests/value/oracle/cache_supplied.N.res.oracle`. The unit tests
named below are in the module `Cache_laws` of
[`plugins/eva/src/utils/unit_tests.ml`](../../../plugins/eva/src/utils/unit_tests.ml),
run by
[`plugins/eva/tests/value/unit_tests.i`](../../../plugins/eva/tests/value/unit_tests.i).
As the other tests of that module, they print only failures.

The laws are those of the accepted resolution of
[issue #13](https://github.com/nyandrianinamamy/frama-c/issues/13#accepted-review-resolution),
written γ for the concretisation:

- `filter` sound: γ(S) ⊆ γ(`filter` B S).
- `relate` sound: when B is closed in S (`relate` B S ⊆ B), membership in
  γ(`filter` B S) depends only on the blocks of B, and γ(S) is the set of
  memories of γ(`filter` B S) that agree outside B with a memory of γ(S);
  `relate` B S returns only blocks that exist in S.
- `filter` exact on the stored input: for K closed in S and γ(S) not empty,
  every memory of γ(`filter` K S) agrees on K with a memory of γ(S).
- `reuse` sound: γ(`reuse` W cur out) contains every memory of γ(out) that
  agrees outside W with a memory of γ(cur).

The Lean model does not state these laws yet; that is the work of
[issue #35](https://github.com/nyandrianinamamy/frama-c/issues/35). No entry
of this file is proved in Lean.

## Concretisation of a cvalue state

**Claim.** The arguments of this file read a state of the cvalue domain
`(m, clob)` as follows. γ(`Bottom`) is empty and γ(`Top`) holds every memory.
A memory is in γ(`Map` m) when, for each block b bound in m, the content of b
is described by the offsetmap m(b). A block not bound in m is not
constrained. The clobbered set `clob` does not constrain memories: it lists
the blocks that may hold the address of a local or formal variable, which the
end of a scope sweeps. So γ(m) is a conjunction of one constraint per bound
block, each depending on that block alone: cvalue is not relational.

**Kind.** Relied on from Eva.

**Contract cited.** `Lmap_sig.S`
([`src/kernel/services/abstract_interp/lmap_sig.ml`](../../../src/kernel/services/abstract_interp/lmap_sig.ml)):
a state is `Bottom`, `Top` or a map from bases to offsetmaps; `filter_by_shape`
removes the bases outside the given set; `merge ~into t` adds all bindings of
`t` into `into`. `Locals_scoping.clobbered_set`
([`locals_scoping.mli`](../../../plugins/eva/src/domains/cvalue/locals_scoping.mli)).
The documentation of `filter` in `Abstract_domain.Caching`
([`abstract_domain.ml`](../../../plugins/eva/src/domains/abstract_domain.ml)):
`filter B S` keeps the projection on B of γ(S), and says nothing outside B.

**Used by.** The four entries on the laws below.

**Checked.** Not checked: Eva gives no formal concretisation. The reading of an
unbound block differs from the analysis's own: the analysis reads a variable
absent from a map through a default offsetmap, uninitialized
(`Cvalue.Default_offsetmap.default_offsetmap`). The reading above is used for
the filtered states, which the cache only compares and gives to `reuse`. For
the states the analysis continues from, the results of `reuse`, the entry
[`reuse` sound for cvalue](#reuse-sound-for-cvalue) shows that every block
that exists after the call is bound. Offsetmaps describe bit ranges of a
block; the arguments treat a block as a whole, as the model does: proved for
whole blocks, argued for offsets.

**Open.** None for this claim.

## The match by equality

**Claim.** At a call analysed through the body of a function, in an analysis
that uses supplied entries (see [No analysis has both
caches](#no-analysis-has-both-caches)), with cvalue as the only domain and no
consumer of memexec identifiers enabled (see [A supplied entry is used with
cvalue alone and no consumer of memexec
identifiers](#a-supplied-entry-is-used-with-cvalue-alone-and-no-consumer-of-memexec-identifiers)):
the candidates are the entries supplied for the function, oldest first. Let s
be the input of the call. A candidate E with key K, stored input I, written
blocks W and exit states (k_i, o_i) matches when `filter` K s = I and
`relate` K s ⊆ K. The oldest matching candidate is used: the states at the end
of the call are (k_i, `reuse` W s o_i), and the body is not analysed. The
candidates examined before it are rejected with `key-differs` when the first
test fails and `key-unclosed` when the second fails. No argument value, call
site or callstack takes part in the match.

**Kind.** OCaml obligation.

**Depends on.** [Concretisation of a cvalue
state](#concretisation-of-a-cvalue-state). For the soundness of the states
returned: the four entries on the laws below, and the soundness of the entry
itself, which the test module that supplies it owes. The match lemma of the
model ([issue #35](https://github.com/nyandrianinamamy/frama-c/issues/35)) and
the hit theorem ([issue #38](https://github.com/nyandrianinamamy/frama-c/issues/38))
are pending.

**Symbols.** `Cache_entry.Make.make`, `Cache_entry.Make.find`,
`Supplied_entries.supply`, `Supplied_entries.entries`,
`Supplied_entries.Lookup.find`, `Call_cache.Make.lookup`,
`Compute_functions.Make.compute_and_cache_call`.

**Argument.** `make` stores `filter K input` as I and filters each exit state
to K ∪ W, and refuses a key that is not closed in the input: `relate K input`
must be included in K. W is the written set of the footprint with the block
of the returned value, if any. `supply` gives the entries the identifiers 1,
2, ... in the order of the calls to `supply`, and appends each entry to the
list of its function, so the list is ordered from the oldest. `find` examines
the list in order and stops at the first candidate whose `check` succeeds;
`check` compares `Domain.filter K s` with I by `Domain.equal`, then tests
`relate K s` ⊆ K. A failure of either test adds the candidate to the rejected
list with its reason and the next one is examined. `apply` maps `reuse W s`
over the exit states and keeps their partition keys. The lookup takes the
function and the state only, so no argument value, call site or callstack is
compared. The state given to the lookup is the input of the call: the
caller's state after `Domain.start_call`, which binds the formals
(`Transfer_stmt`), so formals take part in the key as blocks. For cvalue,
`Cvalue_domain.State.equal` compares the maps and ignores the clobbered set.
The engine never analyses a call from `Bottom`. On a hit,
`compute_and_cache_call` evaluates the preconditions of the callee at the
call, runs the call hooks with `` `Reuse `` and the results hooks with
`` `Reuse N ``, N being the identifier of the entry, and returns the states as
the result of the call. The caller then finalizes the call as after an
analysed body.

The theorem of the model assumes inclusion of the filtered current input in
the filtered stored input; equality implies it. It needs closure in the
stored input only, which `make` checks. The test on the current input is
kept for equality with an analysis without the cache.

**Evidence.** Executed by run 0 of `cache_supplied.c`; the expected values are
written by hand in the comment of the test file and in its module:

- The first call to `step`, with x = 1 and g = 3, reads
  `lookup: hit (entry 1); execution: not-analysed`, `step` prints nothing for
  it, and `Frama_C_show_each_after_hit` prints `{4}`, the value of out in the
  supplied exit state.
- After `g = 5`, the second call reads
  `lookup: rejected (entry 1: key-differs); execution: analysed`; `step` prints
  `{1}, {5}`; out is `{6}`.
- `precise_first` has entry 3 (out = 7) supplied before entry 4 (out in
  [7..8]); `wide_first` has entry 5 (out in [7..8]) supplied before entry 6
  (out = 7). Both entries of each function match. The calls read
  `hit (entry 3)` and `hit (entry 5)`, and out is `{7}` and `{7; 8}`. The two
  functions have the same body, so the order of supply alone decides.
- The module prints the content of each entry from OCaml: its key, stored
  input, read and written blocks and exit states with their partition keys.
- The counts read `cache-hits 1, cache-rejected-key-differs 1` for `step`.

**Open.**

- `key-unclosed` is not exercised: the `relate` of cvalue returns the empty
  set, so every key is closed (see [`relate` empty for
  cvalue](#relate-empty-for-cvalue)).
- A hit delivers the Exit part only. The statements of a body reached only
  through hits are not marked as reached, and no alarm or status is replayed;
  in run 0 the bodies of `set_out`, `precise_first` and `wide_first` are never
  analysed. These are the tickets on Safety and Reach at a hit
  ([issue #47](https://github.com/nyandrianinamamy/frama-c/issues/47),
  [issue #48](https://github.com/nyandrianinamamy/frama-c/issues/48)).
- The soundness of a supplied entry is not checked beyond the closure of its
  key and the bindings of its exit states (see [`reuse` sound for
  cvalue](#reuse-sound-for-cvalue)). The entries of the fixture are written
  by hand from the bodies they stand for.

## No analysis has both caches

**Claim.** Memexec answers no call of an analysis whose calls are looked up
in the supplied entries, and the supplied entries answer no call of an
analysis whose calls are looked up in memexec. An analysis looks up its calls
in the supplied entries when a test module supplied an entry in the current
project before the analysis started. Option `-eva-no-memexec` disables both.

**Kind.** OCaml obligation.

**Depends on.** None.

**Symbols.** `Supplied_entries.supply`, `Supplied_entries.active`,
`Supplied_entries.Active`, the hook that `Supplied_entries` registers with
`Cvalue_callbacks.register_at_start_hook`, `Analysis.pre_analysis`,
`Call_cache.Make.lookup`, `Call_cache.Make.store`.

**Argument.** `lookup` reads `-eva-memexec` first and returns no candidate
without consulting a cache when it is not set. Otherwise it tests
`Supplied_entries.active ()`: when it holds, it answers from the supplied
entries and never calls memexec, and the `pending` value it returns is
`Supplied`, for which `store` refuses with `supplied-only` without calling
memexec. When it does not hold, it runs the memexec path, which never reads
the supplied entries. `active` reads a state that only the hook sets: to
whether the table of supplied entries is not empty. `pre_analysis` runs the
hook once, through `Cvalue_callbacks.apply_at_start_hooks`, before the
analysis computes any call, so every call of an analysis takes the same
branch, even if entries are supplied during it. The table is filled only by
`Supplied_entries.supply`. No module of the analyzer calls it: Eva exports the
module in its internal API, marked for tests only, and the only caller in the
tree is the test module `cache_supplied.ml`. The selection is made at run
time; no build option changes it.

**Evidence.** Executed by run 3 of `cache_supplied.c`, with Inout loaded, in
which memexec would store the first call to `plain(1)` and hit the second, as
it does for `leaf` in `cache_dispositions.c` and in `call-cache.t`. Both calls
to `plain` read `lookup: no-candidate; execution: analysed; storage: refused
(supplied-only)`, `plain` prints its argument twice, and the counts of `plain`
read `memexec-hits 0, memexec-stored 0`. Executed by run 2: with
`-eva-no-memexec`, every call reads `lookup: no-candidate` and
`storage: refused (disabled)`. Analyses without supplied entries take the
memexec path; see [the seam does not change the results of an
analysis](call-cache-seam.md#the-seam-does-not-change-the-results-of-an-analysis).

**Open.** No fixture supplies an entry while an analysis runs; that such an
entry is not used by that analysis rests on source inspection.

## A supplied entry is used with cvalue alone and no consumer of memexec identifiers

**Claim.** When the domains of the analysis are not the cvalue domain alone,
every supplied candidate is rejected with `product`. When the Inout or From
plug-in is loaded, or the analysis of threads is enabled, every supplied
candidate is rejected with `consumer`. In both cases the body is analysed.

**Kind.** OCaml obligation.

**Depends on.** None.

**Symbols.** `Supplied_entries.Lookup.cvalue_alone`,
`Supplied_entries.consumer_enabled`, `Supplied_entries.Lookup.find`.

**Argument.** `cvalue_alone` is defined only when the structure of the
product is a single leaf whose key is the key of `Cvalue_domain.State`; the
key comparison gives an equality between the type of the states of the engine
and that of cvalue states, through which the input of the call and the
states returned are converted, with no change of value. Any other structure,
a product of several domains included, rejects every candidate. The second
test is needed because a hit sends its identifier to the results hooks with
`` `Reuse N ``: Inout (`Operational_inputs.record_for_callwise_inout`) and
From (`Callwise.record_for_individual_froms`) look it up in their tables of
memexec results with `MemExec.find`, and the analysis of threads
(`Mt_analysis_hooks.catch_functions_record`) in its own table; the
identifier of a supplied entry is in none of them. The test is on the
presence of the plug-ins (`Plugin.is_present`), so it also rejects when From
is loaded without `-calldeps`, where its hook records nothing.

**Evidence.** Executed by run 0: the default product is a single cvalue leaf,
and the calls hit. Run 1, with `-eva-domains cvalue,sign`: every call to a
function with supplied entries reads `rejected (entry N: product)` for each of
its entries and is analysed. Run 3, with Inout loaded: every such call reads
`rejected (entry N: consumer)` and is analysed. Not executed: From, the
analysis of threads.

**Open.** A plug-in outside the tree that registers a results hook and reads
`` `Reuse N `` is not detected. The registration of parts that will let Inout
and From be served by an entry is
[issue #53](https://github.com/nyandrianinamamy/frama-c/issues/53).

## `filter` sound for cvalue

**Claim.** For every set of blocks B and cvalue state S,
γ(S) ⊆ γ(`filter` B S).

**Kind.** Argued in prose.

**Depends on.** [Concretisation of a cvalue
state](#concretisation-of-a-cvalue-state).

**Argument.** `Cvalue_domain.State.filter B (m, clob)` is
`(Cvalue.Model.filter_by_shape B m, clob)`
([`cvalue_domain.ml`](../../../plugins/eva/src/domains/cvalue/cvalue_domain.ml)).
`filter_by_shape` returns `Top` on `Top`, `Bottom` on `Bottom`, and on a map
keeps the bindings of the blocks of B, unchanged
([`lmap.ml`](../../../src/kernel/services/abstract_interp/lmap.ml),
`inter_with_shape`). On `Top` and `Bottom` γ is unchanged. On a map, the
filtered state binds a subset of the blocks, each to the same offsetmap, so
it imposes a subset of the constraints and its γ contains γ(m). This is the
weak form of the law: `filter` only forgets.

**Evidence.** Unit tests of `Cache_laws`, on five states (the empty map, two
maps with integers, an uninitialized block and pointers, `Top` and `Bottom`)
and on the 16 sets of blocks among four variables: `filter B S` binds exactly
the blocks of B bound in S, each to its offsetmap in S, and is S on `Top` and
`Bottom`; and `filter` is idempotent. The unit-test oracle prints no failure.
A mutation of `filter` into the identity made them print 27 failures; the
mutation was reverted.

**Open.** The law in the Lean model, pending
([issue #35](https://github.com/nyandrianinamamy/frama-c/issues/35)).

## `filter` exact on the stored input for cvalue

**Claim.** For a cvalue state S with γ(S) not empty and every set of blocks K,
every memory of γ(`filter` K S) agrees on K with a memory of γ(S).

**Kind.** Argued in prose.

**Depends on.** [Concretisation of a cvalue
state](#concretisation-of-a-cvalue-state), [`filter` sound for
cvalue](#filter-sound-for-cvalue) for the form of `filter`.

**Argument.** If S is `Top`, `filter K S` is `Top` and the memory itself is
the witness. S is not `Bottom` since γ(S) is not empty. Let S be a map m, σ₀ a
memory of γ(m), and σ a memory of γ(`filter` K m). Build σ' equal to σ on the
blocks of K and to σ₀ elsewhere. For a block b bound in m: if b is in K,
`filter` keeps m(b), so σ'(b) = σ(b) is described by m(b); otherwise
σ'(b) = σ₀(b) is described by m(b). So σ' is in γ(m) and agrees with σ on K.
The closure of K is not used: cvalue is not relational. Non-emptiness is: on
a state whose γ is empty, `filter` can forget the block that makes it empty.

**Evidence.** Source inspection, and the unit tests of `filter` above for the
form of `filter`. The witness construction is not executable.

**Open.** Whether a cvalue map with an offsetmap whose γ is empty can reach
the store, which would make the non-emptiness hypothesis fail, is not
examined. The law in the Lean model, pending
([issue #35](https://github.com/nyandrianinamamy/frama-c/issues/35)).

## `relate` empty for cvalue

**Claim.** `relate` of cvalue returns the empty set, which satisfies the law
`relate` sound: every set of blocks B is closed in every state S, membership
in γ(`filter` B S) depends only on the blocks of B, γ(S) is the set of
memories of γ(`filter` B S) that agree outside B with a memory of γ(S), and
`relate` returns no block that does not exist in S.

**Kind.** Argued in prose.

**Depends on.** [Concretisation of a cvalue
state](#concretisation-of-a-cvalue-state), [`filter` sound for
cvalue](#filter-sound-for-cvalue).

**Argument.** `Cvalue_domain.State.relate _ _` is `Base.SetLattice.empty`, so
`relate B S` ⊆ B for every B and S, and it returns no block at all. On a map
m, `filter B m` binds only blocks of B, and each constraint concerns one
block, so membership in γ(`filter` B m) depends only on the blocks of B. A
memory of γ(m) is in γ(`filter` B m) (`filter` sound) and agrees with itself.
Conversely, let σ be in γ(`filter` B m) and agree outside B with σ₁ in γ(m):
for a bound block in B, σ(b) is described by m(b) through the filtered
state; for a bound block outside B, σ(b) = σ₁(b) is described by m(b). So σ
is in γ(m). On `Top` and `Bottom` the decomposition is immediate.

**Evidence.** Source inspection
([`cvalue_domain.ml`](../../../plugins/eva/src/domains/cvalue/cvalue_domain.ml),
`relate`). Executed: every supplied key of run 0 is accepted as closed by
`Cache_entry.Make.make` and at each lookup.

**Open.** The law in the Lean model, pending
([issue #35](https://github.com/nyandrianinamamy/frama-c/issues/35)).

## `reuse` sound for cvalue

**Claim.** For cvalue states cur and out and a set of blocks W such that out
binds every block of W that cur binds, γ(`reuse` W cur out) contains every
memory of γ(out) that agrees outside W with a memory of γ(cur). At a hit on a
supplied entry, out is an exit state of the entry, W its written blocks and
cur the input of the call: the condition holds, and the result binds every
block that exists after the call.

**Kind.** Argued in prose.

**Depends on.** [Concretisation of a cvalue
state](#concretisation-of-a-cvalue-state).

**Argument.** `Cvalue_domain.State.reuse _ ~current_input:(c, _)
~previous_output:(o, clob)` is `(Cvalue.Model.merge ~into:c o, clob)`: it
ignores W and takes the bindings of o over those of c
(`Lmap.merge`, `decide _ _ v2 = v2`); when c or o is `Top` or `Bottom`, the
result is o. If o is `Bottom`, γ(o) is empty. If o is `Top`, the result is
`Top`. If c is `Bottom`, no memory agrees with one of γ(c), and if c is `Top`
the result is o, whose γ contains γ(o). Otherwise let σ be in γ(o) and agree
outside W with σ_c in γ(c). For a block bound in o, the result binds o(b)
and σ(b) is described by it. For a block bound in c and not in o, b is not in
W by the condition, so σ(b) = σ_c(b) is described by c(b), which the result
binds. So σ is in γ of the result.

The condition is not a property of `reuse`: it is checked when an entry is
supplied. `Supplied_entries.supply` refuses an entry whose exit state does
not bind a written block that exists at the exit of the body: every block of
W except the locals of its inner blocks, which leave their scope before the
exit. Those locals are not bound in cur either: cur is the input of a call,
and recursion is outside the scope of the cache. `supply` also refuses an
input that is `Top` or `Bottom`, so the stored input of an entry is a map,
which `filter K Top` = `Top` never equals: no call from `Top` hits, and the
case where the result is out alone does not arise. A block bound in cur
exists after the call when the body frees no block and ends the lifetime of
no block other than its own locals; the spec refuses entries for other
bodies, and the test module owes it for the entries it supplies. So every
block that the analysis may read after the call is bound in the result: from
cur if it is not written, from out otherwise; the return block is among the
written blocks.

The clobbered set of the result is that of out. `finalize_call` adds it to
the clobbered set of the caller, as after an analysed body
([`cvalue_domain.ml`](../../../plugins/eva/src/domains/cvalue/cvalue_domain.ml),
`finalize_call`). `supply` sets it to the blocks of the exit state bound to a
value that may contain the address of a local or formal variable
(`Locals_scoping.offsetmap_contains_local`), so it covers every holder of
such an address that the exit state describes.

**Evidence.** Unit tests of `Cache_laws`: for the five states S, the 16 sets
K and the 16 sets W, `reuse W S (filter (K ∪ W) S)` is equal to S. The
unit-test oracle prints no failure; a mutation of `reuse` that returns the
stored output made them print 287 failures, and was reverted. Executed by run
0 of `cache_supplied.c`: the entry of `set_out` writes out = 7 and its
supplied exit state binds keep to 0; the stored exit state no longer binds
keep, as the module prints (`exit of set_out binds keep: false`), and after
the hit `Frama_C_show_each_after_frame` prints `{7}, {42}`: out from the exit
state, keep = 42 from the caller. The module also supplies an entry whose
exit state does not bind out, and one whose input is `Top`, and prints their
refusals. The refusal of a `Bottom` input is not executed.

**Open.**

- The unit tests check `reuse` against `filter` on one state, not the law on
  two different states; that rests on the argument above.
- No fixture supplies an exit state that holds the address of a local, so the
  clobbered set built by `supply` is not exercised.
- When entries are stored from the analysis of a body
  ([issue #46](https://github.com/nyandrianinamamy/frama-c/issues/46)), the
  producer owes the same condition on its exit states, and the arguments on
  frees and sweeps move to the collector tickets.
- The law in the Lean model, pending
  ([issue #35](https://github.com/nyandrianinamamy/frama-c/issues/35)).
