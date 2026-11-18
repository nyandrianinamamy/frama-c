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

The footprint of an entry has the four sets of the specification: R, the
blocks the body may read; W, those it may write; W_exit, those it may write
on a path that reaches an exit; W_sure, those it certainly and fully
overwrites on every path that reaches an exit. W_sure ⊆ W_exit ⊆ W. The
footprint is R ∪ W.

Two ptests fixtures supply entries from a test module, run the analysis,
then print the entries and the counts:

- [`plugins/eva/tests/value/cache_supplied.c`](../../../plugins/eva/tests/value/cache_supplied.c)
  with
  [`cache_supplied.ml`](../../../plugins/eva/tests/value/cache_supplied.ml).
  It has six runs, with the message category `cache` enabled: run 0 in the
  default configuration with Eva alone; run 1 with
  `-eva-domains cvalue,sign`; run 2 with `-eva-no-memexec`; run 3 with the
  Inout plug-in loaded; run 4 with the From plug-in loaded, without Inout;
  run 5 with `-mthread`. The expected values are written by hand in the
  comment at the top of the C file and beside each entry in the module.
- [`plugins/eva/tests/value/cache_supplied_keys.c`](../../../plugins/eva/tests/value/cache_supplied_keys.c)
  with
  [`cache_supplied_keys.ml`](../../../plugins/eva/tests/value/cache_supplied_keys.ml),
  on the partition keys of exit states, in two runs: run 0 in the default
  configuration, run 1 with
  `-eva-partition-path 1 -eva-interprocedural-partition-path`.

Their oracles are `plugins/eva/tests/value/oracle/cache_supplied.N.res.oracle`
and `cache_supplied_keys.N.res.oracle`. The unit tests named below are in the
module `Cache_laws` of
[`plugins/eva/src/utils/unit_tests.ml`](../../../plugins/eva/src/utils/unit_tests.ml),
run by
[`plugins/eva/tests/value/unit_tests.i`](../../../plugins/eva/tests/value/unit_tests.i).
As the other tests of that module, they print only failures.

The laws are those of the model, defined in
[`lean/ReuseModel/Domain.lean`](../../../lean/ReuseModel/Domain.lean) and
stated in [Domain laws](domain-laws.md#the-laws-in-the-model): `FilterSound`,
`Closed`, `RelateSound` (clauses `decomposes` and `existing`), `ExactOn` and
`FilterExact`, `ReuseSound`, `Extensional`. The lemmas that use them at the
match are in [Matching](matching.md). The entries below argue in prose that
the cvalue domain meets the hypotheses of these laws, and name the law each
argument instantiates. None of them is a proof: the model has no cvalue
domain, and no theorem relates the cvalue states of Eva to the states of the
model.

## Interpretation of cvalue states and of their projections

**Claim.** The arguments of this file read a cvalue state through its
support, the set of blocks it describes. A state `(m, clob)` with support U
covers a memory σ when, for each block b of U that exists in σ, the content
of b in σ is described by the offsetmap that Eva reads for b in m:

- `Bottom` covers no memory and `Top` covers every memory;
- in a map m, a block of U bound in m is read through its offsetmap; a block
  of U not bound in m is read through the default offsetmap of the block
  (`Cvalue.Model.find_base_or_default`), which is uninitialized for a
  variable and empty for an allocated block;
- a block outside U is not constrained.

The clobbered set `clob` does not constrain memories: it lists the blocks
that may hold the address of a local or formal variable, which the end of a
scope sweeps.

The support of a state that the analysis computes, the current input of a
call and each state that a hit returns included, is every block: this is the
reading of the analysis itself. The cache also holds projections: `filter B
S` has the support of S intersected with B. The stored input of an entry is
a projection on its key K; each stored exit state is a projection on K ∪ W.
Eva's maps do not carry the support: the entry does, through its key and its
footprint.

Under this reading:

- **P1.** For b in B, Eva reads b in `filter B m` and in m through the same
  offsetmap: `filter_by_shape` keeps the binding of b when m binds it, and
  leaves b unbound when m does not. So the projection on B covers exactly
  the memories whose blocks of B are described as in m.
- **P2.** Two projections on the same set that are equal for
  `Cvalue.Model.equal` cover the same memories: equal maps have the same
  bindings, so Eva reads each block through the same offsetmap in both. The
  converse does not hold: a binding to the default offsetmap and no binding
  are read alike and compare unequal, which makes the match stricter, not
  weaker.
- **P3.** For a map c and a map o, Eva reads a block b in
  `reuse W c o` = `merge ~into:c (filter_by_shape W o)` through the
  offsetmap of o when b is in W and bound in o, and through that of c
  otherwise. When every block of W bound in c is also bound in o, this is o
  for every block of W and c for every other block: the result is the
  combination of the two states, block by block.

The reading "absent means unconstrained", used by an earlier version of this
file for every state, is wrong for an executable state: Eva reads `x` in the
empty map as uninitialized, so `filter ∅ {x ↦ 7}` read as an executable
state would not cover a memory where x is 7. Within its support, an absent
binding means what Eva reads; only outside its support is a block
unconstrained.

Offsetmaps describe bit ranges of a block. The arguments of this file read a
block as a whole, as the model does (whole blocks, no offsets, see
[`lean/README.md`](../../../lean/README.md)); no argument is recorded per bit
range.

**Kind.** Relied on from Eva, with the reading of absent bindings argued in
prose.

**Contract cited.** `Lmap_sig.S`
([`src/kernel/services/abstract_interp/lmap_sig.ml`](../../../src/kernel/services/abstract_interp/lmap_sig.ml)):
a state is `Bottom`, `Top` or a map from bases to offsetmaps;
`filter_by_shape` keeps the bases of the given set
([`lmap.ml`](../../../src/kernel/services/abstract_interp/lmap.ml),
`inter_with_shape`); `merge ~into t` takes every binding of `t` over those
of `into`, and returns `t` when either is `Top` or `Bottom`;
`find_base_or_default` reads an unbound base through
`Cvalue.Default_offsetmap.default_offsetmap`
([`cvalue.ml`](../../../src/kernel/services/abstract_interp/cvalue.ml)).
`Locals_scoping.clobbered_set`
([`locals_scoping.mli`](../../../plugins/eva/src/domains/cvalue/locals_scoping.mli)).
The documentation of `filter` and `reuse` in `Abstract_domain.Caching`
([`abstract_domain.ml`](../../../plugins/eva/src/domains/abstract_domain.ml)):
`filter B S` keeps the projection on B of γ(S); `reuse W S2 (filter W S1')`
gives the state after a reused call.

**Used by.** Every entry on the laws below and [A hit takes the blocks of
W_exit from the exit state](#a-hit-takes-the-blocks-of-w_exit-from-the-exit-state).

**Checked.** Eva gives no formal concretisation; the reading of each kind of
offsetmap is not checked. P1, P2 and P3 are by source inspection of `Lmap`;
the unit tests of `Cache_laws` check their consequences on bindings (see the
entries below).

**Open.** None for this claim.

## The match by equality

**Claim.** At a call analysed through the body of a function, in an analysis
that uses supplied entries (see [No analysis has both
caches](#no-analysis-has-both-caches)), with cvalue as the only domain and no
consumer of memexec identifiers enabled (see [A supplied entry is used with
cvalue alone and no consumer of memexec
identifiers](#a-supplied-entry-is-used-with-cvalue-alone-and-no-consumer-of-memexec-identifiers)):
the candidates are the entries supplied for the function, oldest first. Let s
be the input of the call. A candidate E with key K, stored input I, and exit
states (k_i, o_i) matches when `filter` K s = I and `relate` K s ⊆ K. The
oldest matching candidate is used and the body is not analysed; the states
at the end of the call are given by [A hit takes the blocks of W_exit from
the exit state](#a-hit-takes-the-blocks-of-w_exit-from-the-exit-state). The
candidates examined before it are rejected with `key-differs` when the first
test fails and `key-unclosed` when the second fails. No argument value, call
site or callstack takes part in the match.

**Kind.** OCaml obligation.

**Depends on.** [Interpretation of cvalue states and of their
projections](#interpretation-of-cvalue-states-and-of-their-projections). For
the soundness of the states returned: the entries on the laws below, the
entry [The written sets of a supplied entry and its
key](#the-written-sets-of-a-supplied-entry-and-its-key), and the soundness
of the entry itself, which the test module that supplies it owes.

**Symbols.** `Cache_entry.Make.make`, `Cache_entry.Make.find`,
`Supplied_entries.supply`, `Supplied_entries.entries`,
`Supplied_entries.Lookup.find`, `Call_cache.Make.lookup`,
`Compute_functions.Make.compute_and_cache_call`.

**Argument.** `make` stores `filter K input` as I, and refuses a key that is
not closed in the input: `relate K input` must be included in K. `supply`
gives the entries the identifiers 1, 2, ... in the order of the calls to
`supply`, and appends each entry to the list of its function, so the list is
ordered from the oldest. `find` examines the list in order and stops at the
first candidate whose `check` succeeds; `check` compares `Domain.filter K s`
with I by `Domain.equal`, then tests `relate K s` ⊆ K. A failure of either
test adds the candidate to the rejected list with its reason and the next
one is examined. The lookup takes the function and the state only, so no
argument value, call site or callstack is compared. The state given to the
lookup is the input of the call: the caller's state after
`Domain.start_call`, which binds the formals (`Transfer_stmt`), so formals
take part in the key as blocks. For cvalue, `Cvalue_domain.State.equal`
compares the maps and ignores the clobbered set. The engine never analyses a
call from `Bottom`. On a hit, `compute_and_cache_call` evaluates the
preconditions of the callee at the call, runs the call hooks with
`` `Reuse `` and the results hooks with `` `Reuse N ``, N being the
identifier of the entry, and returns the states as the result of the call.
The caller then finalizes the call as after an analysed body.

The match lemma of the model (`ReuseModel.Domain.match_lemma`, [Match
lemma](matching.md#match-lemma)) applies with C the current input s, S the
input given to `supply`, and K the key, under the reading above:

- hypothesis 2, `filter` sound on C: by P1, s covers fewer memories than its
  projection on K ([`filter` sound for cvalue](#filter-sound-for-cvalue));
- hypothesis 3, the inclusion of `filter K C` in `filter K S`: both are
  projections on K and they are equal, so by P2 they cover the same
  memories;
- hypothesis 4, `ExactOn K S`: [`filter` exact on the stored input for
  cvalue](#filter-exact-on-the-stored-input-for-cvalue), which keeps a
  premise open;
- hypothesis 5, s covers the current memory: relied on from Eva, as in the
  model.

The lemma needs closure in the stored input only, which `make` checks. The
test on the current input is kept for equality with an analysis without the
cache.

**Evidence.** Executed by run 0 of `cache_supplied.c`:

- The first call to `step`, with x = 1 and g = 3, reads
  `lookup: hit (entry 1); execution: not-analysed`, `step` prints nothing for
  it, and `Frama_C_show_each_after_hit` prints `{4}, {3}, {0}`: out, g and
  keep, the whole state visible to the caller after the call, as in the exit
  state of entry 1 for out and g and as in the caller for keep. The
  assertions `hit_out: out == 4`, `hit_g: g == 3` and `hit_keep: keep == 0`,
  placed before the next assignment, are valid.
- After `g = 5`, the second call reads
  `lookup: rejected (entry 1: key-differs); execution: analysed`; `step` prints
  `{1}, {5}`; out is `{6}` and the assertion `miss: out == 6` is valid.
- `precise_first` has entry 3 (out = 7) supplied before entry 4 (out in
  [7..8]); `wide_first` has entry 5 (out in [7..8]) supplied before entry 6
  (out = 7). Both entries of each function match. The calls read
  `hit (entry 3)` and `hit (entry 5)`, and out is `{7}` and `{7; 8}`; the
  assertion `older: out == 7` after `precise_first` is valid. The two
  functions have the same body, so the order of supply alone decides.
- The first call to `twice(3)` hits entry 10, and the assertion
  `returned: r == 6` is valid; the second, `twice(4)`, reads
  `rejected (entry 10: key-differs)` and is analysed.
- The module prints the content of each entry from OCaml: its key, stored
  input, the four sets of its footprint and its exit states with their
  partition keys.
- The counts read `cache-hits 1, cache-rejected-key-differs 1` for `step` and
  for `twice`.

In runs 1 to 5 no candidate is used, every body is analysed, and the same
assertions are valid: the hand-checked values agree with those of the
analysed bodies.

**Open.**

- `key-unclosed` is not exercised: the `relate` of cvalue returns the empty
  set, so every key is closed (see [`relate` empty for
  cvalue](#relate-empty-for-cvalue)).
- A hit delivers the Exit part only. The statements of a body reached only
  through hits are not marked as reached, and no alarm or status is replayed;
  in run 0 several bodies are never analysed. These are the tickets on Safety
  and Reach at a hit
  ([issue #47](https://github.com/nyandrianinamamy/frama-c/issues/47),
  [issue #48](https://github.com/nyandrianinamamy/frama-c/issues/48)).
- The hypotheses of the match lemma that stay open for cvalue are listed
  under [`filter` exact on the stored input for
  cvalue](#filter-exact-on-the-stored-input-for-cvalue).

## The written sets of a supplied entry and its key

**Claim.** An entry is built only when W_sure ⊆ W_exit ⊆ W and when its key
contains R ∪ (W_exit \ W_sure), the matching key of the specification before
closure. The block that holds the value returned by the function is added to
W, W_exit and W_sure. Nothing checks that the sets describe the body: the
test module that supplies an entry owes the obligations listed in the
documentation of `Supplied_entries.supply`, and a false entry gives a false
result at a hit.

**Kind.** OCaml obligation for the checks; obligation of the supplier for the
rest.

**Depends on.** None.

**Symbols.** `Cache_entry.footprint`, `Cache_entry.Make.make`,
`Supplied_entries.supply`, `Supplied_entries.return_variable`.

**Argument.** `make` first adds the return block, if any
(`Library_functions.get_retres_vi`), to the three written sets: the value
returned is written on every path that reaches an exit, so it is in W_sure,
and the key rule does not require it in the key, which no input binds. It
then raises `Invalid_argument` when the sets are not nested, then when the
key misses a block of R ∪ (W_exit \ W_sure), naming the missing blocks, then
when the key is not closed. A block of W_exit \ W_sure may keep its input
value at an exit, so the exit value depends on its input value: it must be
in the key. A block of W \ W_exit is written only on paths that reach no
exit; it need not be in the key because a hit does not take it from the exit
state (next entry).

The obligations of the supplier, stated in `supplied_entries.mli`: R covers
every block that the body may read, through a pointer included, and a block
designated by a pointer of the key is not in the key unless listed; W covers
every block the body may write, W_exit every block the body may write on a path
that reaches an exit, even when the write leaves the input value, and W_sure only blocks fully overwritten on
every path to an exit; the body neither frees nor allocates a block nor ends
the lifetime of a block other than its own locals; each exit state already
holds the effect of leaving the scope of the locals of the body on the
blocks that may hold their addresses. For instance, an entry for `step`
whose body reads a block outside R gives at a hit the value written in its
exit state, whatever the body would compute: the reviewer of issue #45
changed `step` to read `keep` without changing its entry, and the hit
returned 4 where the body gives 5.

**Evidence.** Executed by run 0 of `cache_supplied.c`. The module prints the
refusals of three entries: `the key does not contain {keep}, of R ∪ (W_exit
\ W_sure)` for a key that misses the read block keep; `the key does not
contain {out}` for out in W_exit and not in W_sure with an empty key; and
`the written sets are not nested` for out in W_exit and not in W. The entry
of `twice` prints `\result<twice>` in its three written sets, and its exit
state binds it; the hit returns 6. The entry of `set_out` has R = ∅: its
marker prints a constant and reads nothing, so the empty key contains R.

**Open.** The obligations of the supplier are not checked. The producer of
entries ([issue #46](https://github.com/nyandrianinamamy/frama-c/issues/46))
takes them over from the collector
([Body access collector](body-access.md#whole-block-observations-and-exits)),
whose W_exit is an upper bound and W_sure a lower bound.

## A hit takes the blocks of W_exit from the exit state

**Claim.** At a hit on an entry with W_exit as its set of blocks written on
a path to an exit, each state at the end of the call is
`reuse W_exit s o_i` for the input s of the call and each stored exit state
o_i, with its partition key: for cvalue, the blocks of W_exit come from o_i
and every other block from s. The blocks of the key outside W_exit and those
of W \ W_exit keep the value they have in s, whatever o_i holds for them.
o_i is stored as supplied, filtered to K ∪ W.

**Kind.** OCaml obligation.

**Depends on.** [Interpretation of cvalue states and of their
projections](#interpretation-of-cvalue-states-and-of-their-projections), P3.

**Symbols.** `Cache_entry.Make.apply`, `Cache_entry.Make.make`,
`Cvalue_domain.State.reuse`, `Supplied_entries.check_exit`.

**Argument.** `make` filters each exit state to K ∪ W. `apply` maps
`Domain.reuse written_exit ~current_input:s ~previous_output:o_i` over the
exit states and keeps their partition keys. `Cvalue_domain.State.reuse W`
filters the output to W before it merges it into the input, so by P3 it
takes from o_i the blocks of W_exit that o_i binds and nothing else.
`check_exit` refuses an entry whose exit state does not bind a block of
W_exit that exists at the exit of the body, every block of W_exit except the
locals of its inner blocks. Those locals are not bound in s either: s is the
input of a call, and recursion is outside the scope of the cache. So the
condition of P3 holds, and the result reads each block of W_exit as o_i and
each other block as s.

Before this change, `Cvalue_domain.State.reuse` ignored its set and copied
every binding of the stored output, and `apply` passed W. A hit then took
from o_i every block of K ∪ W: the key blocks reduced on the path to the exit,
and the blocks written only on paths that never return, at the value they
had in the input of the producer. Memexec passes to `reuse` the set to which
it filtered its outputs (`Mem_exec.store_cacheable_call`, `all_output_bases`,
and `find_match_in_previous`), on which the filter changes nothing; the
default and configuration ptests show no change of its results.

Why W_exit and not W: a block b of W \ W_exit is written only on paths that
reach no exit. An execution that returns does not write it, so its value at
the exit is its value in the input of the call, which can differ from the
producer's when b is not in the key; the stored exit state holds the
producer's. The model of [issue #36](https://github.com/nyandrianinamamy/frama-c/issues/36),
in review and not in this tree, states the agreement of the exit on W_exit,
with a key that contains R ∪ (W_exit \ W_sure). The specification says that
`reuse` takes the written set from the footprint of the entry, R ∪ W; this
operation applies the law `reuse` sound with W_exit instead, which is the
sound choice. The specification is not changed here.

A domain other than cvalue would need a `reuse` that takes nothing outside
its set from the output; the signature `Cache_entry.Domain` states it. Only
cvalue reaches the operation in this version.

**Evidence.** Executed by run 0 of `cache_supplied.c`:

- `loop_on_4` loops forever when g is 4. Entry 7 has the key {x, g} with
  x = 1 and g in {3; 4}, W = W_exit = {out}, and the exit state of the path
  that returns, g = 3 and out = 4. The call, from g in {3; 4}, hits, and
  `Frama_C_show_each_after_loop_on_4` prints `{4}, {3; 4}`: g keeps the
  value of the caller; the assertion `loop_out: out == 4` is valid. Runs 1 to
  5 analyse the body and print `{4}, {3}`: the reduction of g is lost on the
  hit, which is sound.
- `write_then_spin` writes b and loops forever when `choice` is not zero, and
  returns with out = 5 otherwise. Entry 8 has the key {choice}, W = {b, out},
  W_exit = W_sure = {out}, and an exit state that holds b = 0, the value of
  the producer's input. The caller sets b = 1; after the hit
  `Frama_C_show_each_after_write_then_spin` prints `{5}, {1}`, and the
  assertions `spin_out: out == 5` and `spin_b: b == 1` are valid.
- The entry of `set_out` writes out = 7 and its supplied exit state binds
  keep to 0; the stored exit state no longer binds keep (`exit of set_out
  binds keep: false`), and after the hit `Frama_C_show_each_after_frame`
  prints `{7}, {42}`. The assertions `written: out == 7` and
  `kept: keep == 42` are valid.

Before the change, on the same entries at revision `b8a8ca0b46` (a scratch
copy of these cases built against the previous interface), the hit of
`loop_on_4` printed `{4}, {3}` and that of `write_then_spin` printed
`{5}, {0}`. With `apply` changed back to W, run 0 prints `{5}, {0}` and the
assertion `spin_b` is invalid; the mutation was reverted.

**Open.** None for this claim; the soundness of a hit is under [`reuse`
sound for cvalue](#reuse-sound-for-cvalue).

## The exit states of a supplied entry

**Claim.** An exit state of a supplied entry is neither `Top` nor `Bottom`.
A body that never returns has the empty list of exit states, and a hit on
its entry returns no state, so the statement after the call is not reached.
Each exit state is supplied with its partition key, which a hit returns with
the state. Each exit state records as possible holders of the address of a
local or formal variable the blocks it binds to a value that may contain
such an address.

**Kind.** OCaml obligation.

**Depends on.** [Interpretation of cvalue states and of their
projections](#interpretation-of-cvalue-states-and-of-their-projections).

**Symbols.** `Supplied_entries.supply`, `Supplied_entries.check_exit_state`,
`Supplied_entries.holders`, `Supplied_entries.empty_key`,
`Supplied_entries.case_key`, `Cache_entry.Make.apply`,
`Transfer_stmt.do_one_call`, `Cvalue_domain.State.leave_scope`.

**Argument.** `reuse W s Top` is `Top`, since `merge` returns its second
argument when it is `Top`: a hit would lose every block of the caller. An
exit state `Bottom` covers no execution, so it says nothing; the empty list
says that no execution returns. `supply` refuses both, with the input `Top`
or `Bottom` as before. `apply` maps over the list of exit states, so an
empty list gives a hit with no state, which the engine handles as a call
that does not return. `supply` keeps the partition key given with each exit
state, and `apply` returns each state with its key; `Trace_partitioning`
then combines it with the key of the caller as for an analysed body.
`case_key kf n` is a key with one branch: the n-th case of a disjunction at
the return statement of kf, as the iterator records it. The holders are those of the
state as supplied; `Cvalue_domain.State.reuse` returns them as the clobbered
set of the result. In the caller, as after an analysed body,
`Transfer_stmt.do_one_call` makes the formals and locals of the callee leave
scope in each returned state: `Cvalue_domain.State.leave_scope` marks as
escaping the addresses of those variables held by the blocks of the
clobbered set (`Locals_scoping.make_escaping_fundec`); `finalize_call` then
adds the set to that of the caller.

**Evidence.**

- Run 0 of `cache_supplied.c`: the module prints the refusals `an exit state
  is Top` and `an exit state is Bottom; a body that never returns has no
  exit state`. Entry 9, for `never_returns`, has no exit state; the call in
  `if (choice)` hits, and `Frama_C_show_each_unreachable` after it is never
  printed.
- Run 0: `leak_address` stores the address of its formal x in p. Entry 11
  has an exit state with p bound to `&x`. After the hit, the analysis warns
  `locals {x} escaping the scope of leak_address through p`, as runs 1 to 5,
  which analyse the body, do, and the assertion `escaping: \dangling(&p)` is
  valid. With `supply` changed to record no holder, the warning disappears
  and the assertion is invalid; the mutation was reverted.
- `cache_supplied_keys.c`: entry 1 of `choose` has two exit states, out = 1
  with `case_key choose 0` and out = 2 with `case_key choose 1`; the module
  prints them with their keys `[@11#0]` and `[@11#1]`. Run 1 keeps the
  partitioning of a callee through its return, and
  `Frama_C_show_each_after_choose` prints `{1}` and `{2}` apart; run 0 drops
  it and prints `{1; 2}`. With `supply` changed to give every state the
  empty key, run 1 prints `{1; 2}`; the mutation was reverted.

**Open.** No fixture covers the address of a local of an inner block stored
in a block that outlives it, the sweep on the unit's own locals of the
specification: the supplier owes the effect of that sweep in the exit state,
and nothing checks it.

## No analysis has both caches

**Claim.** Memexec answers no call of an analysis whose calls are looked up
in the supplied entries, and the supplied entries answer no call of an
analysis whose calls are looked up in memexec. An analysis looks up its calls
in the supplied entries when a test module supplied an entry in the current
project before the analysis started; that choice holds for the whole
analysis. Within an analysis that uses the supplied entries, each lookup
reads the entries supplied at that time: an entry supplied during the
analysis, by a callback for instance, is a candidate for the later calls of
that analysis. Option `-eva-no-memexec` disables both.

**Kind.** OCaml obligation.

**Depends on.** None.

**Symbols.** `Supplied_entries.supply`, `Supplied_entries.active`,
`Supplied_entries.Active`, `Supplied_entries.entries`, the hook that
`Supplied_entries` registers with `Cvalue_callbacks.register_at_start_hook`,
`Analysis.pre_analysis`, `Call_cache.Make.lookup`, `Call_cache.Make.store`.

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
branch. The candidates of a lookup are read by `Supplied_entries.entries` at
that lookup, from the table that `supply` appends to; nothing freezes the
table during an analysis. The table is filled only by
`Supplied_entries.supply`. No module of the analyzer calls it: Eva exports
the module in its internal API, marked for tests only, and the only callers
in the tree are the test modules `cache_supplied.ml` and
`cache_supplied_keys.ml`. The selection is made at run time; no build option
changes it.

**Evidence.** Executed by runs 3, 4 and 5 of `cache_supplied.c`, in which
memexec would store the first call to `plain(1)` and hit the second, as it
does for `leaf` in `cache_dispositions.c` and in `call-cache.t`. Both calls
to `plain` read `lookup: no-candidate; execution: analysed; storage: refused
(supplied-only)`, `plain` prints its argument twice, and the counts of `plain`
read `memexec-hits 0, memexec-stored 0`. Executed by run 2: with
`-eva-no-memexec`, every call reads `lookup: no-candidate` and
`storage: refused (disabled)`. Analyses without supplied entries take the
memexec path; see [the seam does not change the results of an
analysis](call-cache-seam.md#the-seam-does-not-change-the-results-of-an-analysis).

**Open.** No fixture supplies an entry while an analysis runs: that such an
entry is not used by an analysis that started with memexec, and is a
candidate for the later calls of an analysis that started with supplied
entries, rests on source inspection.

## A supplied entry is used with cvalue alone and no consumer of memexec identifiers

**Claim.** When the domains of the analysis are not the cvalue domain alone,
every supplied candidate is rejected with `product`. Otherwise, when the
Inout or From plug-in is loaded, or the analysis of threads is enabled, every
supplied candidate is rejected with `consumer`. In both cases the body is
analysed. `product` takes precedence over `consumer`, and both over the
examination of each candidate (`key-differs`, `key-unclosed`).

**Kind.** OCaml obligation.

**Depends on.** None.

**Symbols.** `Supplied_entries.Lookup.cvalue_alone`,
`Supplied_entries.consumer_enabled`, `Supplied_entries.Lookup.find`.

**Argument.** `find` tests `cvalue_alone` first, then `consumer_enabled`,
then calls `Cache_entry.Make.find`; the first test that rejects gives its
reason to every candidate. `cvalue_alone` is defined only when the structure
of the product is a single leaf whose key is the key of `Cvalue_domain.State`;
the key comparison gives an equality between the type of the states of the
engine and that of cvalue states, through which the input of the call and the
states returned are converted, with no change of value. Any other structure,
a product of several domains included, rejects every candidate. The second
test is needed because a hit sends its identifier to the results hooks with
`` `Reuse N ``: Inout (`Operational_inputs.record_for_callwise_inout`) and
From (`Callwise.record_for_individual_froms`) look it up in their tables of
memexec results with `MemExec.find`, and the analysis of threads
(`Mt_analysis_hooks.catch_functions_record`) in its own table; the
identifier of a supplied entry is in none of them. The test is on the
presence of the plug-ins (`Plugin.is_present`), so it also rejects when From
is loaded without `-calldeps`, where its hook records nothing. `-mthread`
does not add a domain, so the product stays cvalue alone and the thread test
is reached.

**Evidence.** Executed by run 0: the default product is a single cvalue leaf,
and the calls hit. Run 1, with `-eva-domains cvalue,sign`: every call to a
function with supplied entries reads `rejected (entry N: product)` for each of
its entries and is analysed. Runs 3, 4 and 5, with Inout loaded, with From
loaded without Inout, and with `-mthread`: every such call reads
`rejected (entry N: consumer)` and is analysed, and the same assertions are
valid. The precedence of `product` over `consumer` rests on source
inspection: no run enables both.

**Open.** A plug-in outside the tree that registers a results hook and reads
`` `Reuse N `` is not detected. The registration of parts that will let Inout
and From be served by an entry is
[issue #53](https://github.com/nyandrianinamamy/frama-c/issues/53).

## The collector with supplied entries

**Claim.** A hit on a supplied entry analyses no body: it gives no
observation to the collector of block accesses, no verdict on its message
and no `collector-` count. A body analysed in an analysis that uses supplied
entries, after a lookup that found no candidate or rejected every candidate,
is observed as any analysed body when recording is enabled (the default;
`-eva-no-cache-collect` disables it): its verdict is counted and, under the
message category `cache`, printed beside `refused (supplied-only)`. The
body stores nothing.

**Kind.** OCaml obligation.

**Depends on.** [Body access collector](body-access.md).

**Symbols.** `Compute_functions.Make.compute_and_cache_call`,
`Body_access.capture`, `Call_cache.Make.store`, `Call_cache.Make.lookup`.

**Argument.** `compute_and_cache_call` wraps the analysis of the body in
`Body_access.capture` only in the branch `No_candidate`, and passes the
footprint to `store`, which prints and counts the verdict whatever the
cache. The branch `Hit` neither captures nor calls `store`; `lookup` prints
the message of the hit without a verdict. The verdict is not read by the
supplied entries, which store nothing.

**Evidence.** Run 0 of `cache_supplied.c`: the hit of `twice(3)` has no
verdict; the analysed call `twice(4)`, after `rejected (entry 10:
key-differs)`, reads `storage: refused (supplied-only); collector:
would-store`; the counts of `twice` read `collector-would-store 1`, for
that call only. The other bodies call a `Frama_C_show_each` builtin and read
`collector: refused (builtin)`.

**Open.** None for this claim.

## `filter` sound for cvalue

**Claim.** The cvalue domain meets `FilterSound`, the weak form of `filter`
sound, under the reading of a projection on its support: for every set of
blocks B and cvalue state S, every memory that S covers is covered by
`filter B S`.

**Kind.** Argued in prose.

**Depends on.** [Interpretation of cvalue states and of their
projections](#interpretation-of-cvalue-states-and-of-their-projections).

**Argument.** `Cvalue_domain.State.filter B (m, clob)` is
`(Cvalue.Model.filter_by_shape B m, clob)`
([`cvalue_domain.ml`](../../../plugins/eva/src/domains/cvalue/cvalue_domain.ml)).
`filter_by_shape` returns `Top` on `Top`, `Bottom` on `Bottom`, and on a map
keeps the bindings of the blocks of B, unchanged. The support of the result
is that of S intersected with B, and by P1 each of its blocks is read as in
S. So the result imposes a subset of the constraints of S, and covers every
memory that S covers. This instantiates `FilterSound`
([Domain laws](domain-laws.md#the-laws-in-the-model)); the match lemma takes
it on the current input only
([the weak form suffices](domain-laws.md#the-weak-form-of-filter-sound-suffices-for-the-match-and-product-lemmas)).

**Evidence.** Unit tests of `Cache_laws`, on five states (the empty map, two
maps with integers, an uninitialized block and pointers, `Top` and `Bottom`)
and on the 16 sets of blocks among four variables: `filter B S` binds exactly
the blocks of B bound in S, each to its offsetmap in S; it is a map when S is
a map, and S when S is `Top` or `Bottom`; and `filter` is idempotent. The
unit-test oracle prints no failure. A mutation of `filter` into the identity
made them print 27 failures; the mutation was reverted.

**Open.** None in the argument. The model has no cvalue domain.

## `filter` exact on the stored input for cvalue

**Claim.** For a cvalue state S that covers some memory and every set of
blocks K, every memory covered by `filter K S` agrees on K with a memory
covered by S: S meets `ExactOn K S`, and cvalue meets `FilterExact`.

**Kind.** Argued in prose, with a premise open for the entries.

**Depends on.** [Interpretation of cvalue states and of their
projections](#interpretation-of-cvalue-states-and-of-their-projections),
[`relate` empty for cvalue](#relate-empty-for-cvalue).

**Argument.** If S is `Top`, `filter K S` is `Top` and the memory itself is
the witness. S is not `Bottom`, since it covers a memory. Let S be a map m,
σ₀ a memory covered by m, and σ a memory covered by `filter K m`. Build σ'
equal to σ on the blocks of K and to σ₀ elsewhere. For a block b of K, Eva
reads b in m as in `filter K m` (P1), so σ'(b) = σ(b) is described there;
for another block, σ'(b) = σ₀(b) is described by m. So σ' is covered by m
and agrees with σ on K. This is `exactOn_of_decomposes` of the model applied
to the decomposition of the next entry, with the combination of two memories
on K that the model calls `Combinable`.

**Evidence.** Source inspection, and the unit tests of `filter` above for the
form of `filter`. The witness construction is not executable.

**Open.** Two premises are not established for the entries:

- the stored input covers some memory (hypothesis `∃ w, γ S w` of the
  product lemma, [Non-emptiness](matching.md#non-emptiness-of-the-stored-concretisation-stays-a-hypothesis)):
  `supply` refuses `Bottom`, not a map that binds a block to an offsetmap
  that describes no content;
- Eva's concrete memories can be combined on any set of blocks
  (`Combinable`, [Matching](matching.md#kinds-of-the-hypotheses)).

## `relate` empty for cvalue

**Claim.** `relate` of cvalue returns the empty set, which meets
`RelateSound`: every set of blocks B is `Closed` in every state S, `filter`
decomposes S on B (clauses `onKey` and `split` of `Decomposes`), and `relate`
returns no block that does not exist in S (clause `existing`).

**Kind.** Argued in prose.

**Depends on.** [Interpretation of cvalue states and of their
projections](#interpretation-of-cvalue-states-and-of-their-projections),
[`filter` sound for cvalue](#filter-sound-for-cvalue).

**Argument.** `Cvalue_domain.State.relate _ _` is `Base.SetLattice.empty`,
never `Top`, so `relate B S` ⊆ B for every B and S, and it returns no block
at all. On a map m, the support of `filter B m` is within B, so membership
in what it covers depends only on the blocks of B (`onKey`). A memory
covered by m is covered by `filter B m` (`filter` sound) and agrees with
itself. Conversely, let σ be covered by `filter B m` and agree outside B
with σ₁ covered by m: for a block of B, σ(b) is described as in m (P1); for
a block outside B, σ(b) = σ₁(b) is described by m. So σ is covered by m
(`split`). On `Top` and `Bottom` the decomposition is immediate.

**Evidence.** Source inspection
([`cvalue_domain.ml`](../../../plugins/eva/src/domains/cvalue/cvalue_domain.ml),
`relate`). Executed: every supplied key of run 0 is accepted as closed by
`Cache_entry.Make.make` and at each lookup.

**Open.** None in the argument. The model has no cvalue domain.

## `reuse` sound for cvalue

**Claim.** Let cur be a cvalue map whose support is every block, out a map
with a support U that contains W, and W a set of blocks such that out binds
every block of W that cur binds. Then `reuse W cur out` covers every memory
that agrees on W with a memory covered by out and outside W with a memory
covered by cur. This is `ReuseSound` of the model restricted by the
condition on bindings: without it the law fails for cvalue, since a block
of W that out does not bind keeps its value of cur, while Eva reads it in
out as uninitialized. The law as the model states it, for every W, cur and
out, is therefore not claimed for cvalue. At a hit, W is W_exit, out an exit state of the entry, with
support K ∪ W, and cur the input of the call: the condition holds.

**Kind.** Argued in prose.

**Depends on.** [Interpretation of cvalue states and of their
projections](#interpretation-of-cvalue-states-and-of-their-projections), [A
hit takes the blocks of W_exit from the exit
state](#a-hit-takes-the-blocks-of-w_exit-from-the-exit-state).

**Argument.** `Cvalue_domain.State.reuse W ~current_input:(c, _)
~previous_output:(o, clob)` is
`(Cvalue.Model.merge ~into:c (filter_by_shape W o), clob)`. Let σ agree on
W with σ_o covered by o and outside W with σ_c covered by c. By P3 and the
condition, Eva reads a block b of W in the result as in o: b is in U, so
σ_o(b) = σ(b) is described there. It reads another block as in c, where
σ_c(b) = σ(b) is described. So σ is covered by the result. The exit states
are maps, since `supply` refuses `Top` and `Bottom`; cur is a map, since no
call is analysed from `Bottom` and a call whose input is `Top` matches no
entry (`filter K Top` is `Top`, and the stored input of an entry is a map).

The hit, as an argument in prose: let σ be a memory covered by the input s
of the call, and τ the memory at the exit of an execution of the body from
σ. By the match ([The match by equality](#the-match-by-equality)), some σ'
covered by the stored input agrees with σ on K. The execution from σ' reads
only blocks of R ⊆ K, so it takes the same path and reaches an exit in τ',
which agrees with τ on W_sure; a block of W_exit \ W_sure is in the key, so
it starts with the same value and ends with the same value: τ and τ' agree
on W_exit. A block outside W_exit is not written by an execution that
reaches an exit: τ agrees with σ outside W_exit. The model's statement of
this step is `ReuseModel.frame_of_not_written`, for a block issued at entry
that no event of the trace writes; the block may be read. Its hypothesis
that the block is issued at entry is not discharged here. τ' is covered by
an exit state as supplied, by the Exit claim of the entry, which the
supplier owes, and so by its projection o_i on K ∪ W (`filter` sound). So τ
agrees on W_exit with a memory covered by o_i and outside W_exit with a
memory covered by s, and the law above puts it in `reuse W_exit s o_i`.

The clobbered set of the result is that of out. `supply` sets it to the
blocks of the exit state bound to a value that may contain the address of a
local or formal variable (`Locals_scoping.offsetmap_contains_local`), so it
covers every holder of such an address that the exit state describes; a
holder outside W_exit keeps the value of s but stays in the set, which only
widens the blocks that `leave_scope` examines after the call. A holder that
only the caller's state describes is not found by this scan of the exit
state; it is in the clobbered set of the caller's state only if the caller
recorded it, and the argument that the result keeps it is not written.

**Evidence.** Unit tests of `Cache_laws`:

- for the five states S, the 16 sets K and the 16 sets W,
  `reuse W S (filter (K ∪ W) S)` is equal to S;
- for every pair of the three maps as current input and stored output, and
  the 16 sets W, `reuse W C O` binds each block of W bound in O to its
  offsetmap in O, each other block bound in C to its offsetmap in C, and no
  other block. The pairs include states that differ outside W.

The unit-test oracle prints no failure. With `reuse` changed back to ignore
its set, the second test prints 54 failures and the first none; the mutation
was reverted. Executed by run 0 of `cache_supplied.c`, for the cases listed
under [A hit takes the blocks of W_exit from the exit
state](#a-hit-takes-the-blocks-of-w_exit-from-the-exit-state).

**Open.**

- The law holds for cvalue only under the condition on bindings; the hit
  supplies it through the check of the exit states by `supply`.
- The step outside W_exit needs the block issued at entry, and the holders
  described only by the caller's state need an argument that the result
  keeps them in the clobbered set.
- An unrolled recursive call reaches the lookup before the check that
  refuses recursion on a miss. No fixture has a recursive function with a
  supplied entry, and the argument above assumes one activation of the body.
- R holds every read, so a block read only after it is surely overwritten
  must still be in the key (`make` refuses the entry otherwise). The key is
  then larger than the incoming values the body depends on. Sound; a finer
  rule needs reads that depend on the incoming value to be told apart.
- The hit theorem of the model
  ([issue #38](https://github.com/nyandrianinamamy/frama-c/issues/38)) and
  the agreement of the exit on W_exit
  ([issue #36](https://github.com/nyandrianinamamy/frama-c/issues/36)) are
  not in this tree: the argument on the hit above is in prose, and its step
  from the key to the agreement on W_exit is not checked.
- When entries are stored from the analysis of a body
  ([issue #46](https://github.com/nyandrianinamamy/frama-c/issues/46)), the
  producer owes the condition on its exit states and the four sets of the
  footprint, and the arguments on frees and sweeps move to the collector
  tickets.
