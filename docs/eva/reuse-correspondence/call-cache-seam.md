# Call-cache seam

Claims about the seam between the analysis of calls and the cache of calls,
`plugins/eva/src/engine/call_cache.ml`, added by
[issue #33](https://github.com/nyandrianinamamy/frama-c/issues/33). Memexec
(`plugins/eva/src/engine/mem_exec.ml`) is the only cache behind the seam. The
regression named in several entries is the ptests fixture
`plugins/eva/tests/value/cache_dispositions.c`, run in the default
configuration with the message category `cache` enabled; its oracles are
`plugins/eva/tests/value/oracle/cache_dispositions.cache.log` and
`plugins/eva/tests/value/oracle/cache_dispositions.stats.log`.

## The seam does not change the results of an analysis

**Claim.** Routing memexec through the seam changes no result of an analysis:
alarms, property statuses, reached statements, states and the calls answered
by memexec are those of the previous engine. Scope: every Eva configuration,
with `-eva-memexec` set or not. The message category `cache` has no verbosity
level, so its lines are printed only when `-eva-msg-key` enables it.

**Kind.** OCaml obligation.

**Symbols.** `Call_cache.Make.lookup`, `Call_cache.Make.store`,
`Compute_functions.Make.compute_and_cache_call`,
`Compute_functions.Make.compute_call_with_target`,
`Mem_exec.Make.reuse_previous_call`, `Mem_exec.Make.store_computed_call`,
`Call_cache.new_counter`, `Call_cache.cleanup_results`.

**Argument.** `lookup` calls `reuse_previous_call` with the function, the
state and the argument values that `compute_and_cache_call` used before, and
only when `-eva-memexec` is set. Otherwise it answers that no entry matches,
and the body is analysed as before. `store` calls memexec under the same
conditions as before: `-eva-memexec` is set and the result is marked
`Cacheable`. The test on `Cacheable` moved from `compute_and_cache_call` into
`store_computed_call`. `store_computed_call` performs the same operations in
the same order as before, and returns the call number or a reason instead of
`unit`. The statistics updates of memexec moved into the seam, and the
category messages are new; neither is read by the analysis. With
`-eva-no-memexec`, the seam counts each lookup as a miss and each storage as
refused for `disabled`, where memexec counted nothing. The iteration
order of the lookup is unchanged. `new_counter` and `cleanup_results` are the
memexec functions, called at the same points of `Iterator` and `Analysis`.

**Evidence.** Source inspection of the change. Executed: the default Eva
ptests (`@plugins/eva/tests/ptests_config`), the ptests of every Eva
configuration (`@plugins/eva/tests/ptests`) and the native Eva tests
(`dune runtest plugins/eva`), all rerun on the changed engine. No existing
ptests oracle changed. Among the oracles that passed, those containing
`Reusing old results for call to` record hits answered through `lookup`, for
example `plugins/eva/tests/value/oracle/memexec.0.res.oracle`. Two cram
tests print what the change adds, and their expected outputs differ: the list
of message categories (`plugins/eva/tests/utils/help-messages.t`) gains the
category `cache`, and the statistics file
(`plugins/eva/tests/utils/statistics.t`) gains `memexec-stored` rows. No
analysis output differs in either test.

**Open.** The two cram expectations above are not updated by the change that
added the seam, so these two tests fail until they are. Equality with the
previous engine is a regression expectation on the Eva test suite, not a
proved property.

## Each refused storage has one stable reason

**Claim.** For each call analysed by its body, `store` ends in exactly one of:
an entry stored, named by its call number; or a refusal with one reason. With
memexec, the reasons are the paths of `store_computed_call` that did not store
an entry before the seam:

| Identifier | Path |
|---|---|
| `disabled` | `-eva-memexec` is not set; memexec is not called. |
| `not-cacheable` | the result is not marked `Cacheable`. |
| `no-inout` | `Transfer_stmt.current_kf_inout` returns `None`. |
| `footprint-top` | an input or output zone given by Inout is `Top` over its bases. |
| `relate-top` | `Domain.relate` returns `Top` during the closure of the key. |
| `relate-unclosed` | the closure of the key is not reached within two iterations. |
| `exception` | `Not_found` or `Kernel_function.No_Statement` is raised while building the entry. |

The identifiers are listed by `-eva-msg-key help` and documented in
`call_cache.mli` and `mem_exec.mli`.

**Kind.** OCaml obligation.

**Symbols.** `Mem_exec.Make.store_computed_call`,
`Mem_exec.Make.store_cacheable_call`, `Mem_exec.bases`,
`Mem_exec.Make.expand_inputs_with_relations`, `Call_cache.refusal_id`,
`Call_cache.Make.store`.

**Argument.** Each `raise TooImprecise` and each silent return of the previous
code is replaced by the reason of its path, and the exception handler keeps
its scope. The `exception` reason covers the handler of `Not_found` and
`No_Statement` that memexec already had; source inspection did not find which
call in its scope can raise them.

**Evidence.** Source inspection. Executed by the fixture: `stored` on the
first call to `leaf`, and `not-cacheable` on the call to `alloc`, which
allocates, and on `main`, which calls it.

**Open.** No regression enables the category on a path that ends in
`disabled`, `no-inout`, `footprint-top`, `relate-top`, `relate-unclosed` or
`exception`. A regression for each of the first five is pending.

## A hit names the entry stored earlier

**Claim.** The entry named by a hit, `hit (entry N)`, is the entry stored by
the earlier call whose message reads `stored (entry N)`.

**Kind.** OCaml obligation.

**Symbols.** `Mem_exec.Make.store_cacheable_call`,
`Mem_exec.Make.find_match_in_previous`, `Call_cache.new_counter`,
`Iterator.Make_Dataflow.merge_results`, `Call_cache.Make.lookup`,
`Call_cache.Make.store`.

**Argument.** `store_cacheable_call` stores `current_counter ()` with the
entry and returns it. `find_match_in_previous` returns the number stored with
the entry it matches, and the seam prints the numbers it receives. The number
identifies one entry: `merge_results` calls `new_counter` once per analysis of
a body, after the calls made by that body, and the storage of the result of
this analysis follows with no other analysis of a body in between. The number
is the one that the callbacks receive with `` `Body `` and `` `Reuse ``.

**Evidence.** Executed by the fixture: the first call to `leaf` reads
`stored (entry 1)` and the second reads `hit (entry 1)`; `leaf` prints its
argument once, so its body is analysed once.

**Open.** None for this claim.

## The statistics agree with the dispositions

**Claim.** Per function, `memexec-hits` counts the calls whose lookup is a
hit, `memexec-misses` those whose lookup found no candidate, `memexec-stored`
the stored entries, and `memexec-refused-REASON` the storages refused for
REASON.

**Kind.** OCaml obligation.

**Symbols.** `Call_cache.Make.lookup`, `Call_cache.Make.store`,
`Statistics.memexec_hits`, `Statistics.memexec_misses`,
`Statistics.memexec_stored`, `Statistics.memexec_refused`.

**Argument.** `lookup` increments the hit or miss count of the called function
where it decides the lookup. `store` increments the stored or refused count
from the same value that it prints.

**Evidence.** Executed by the fixture, from one run: one hit, one stored entry
and one miss for `leaf`; one miss and one `not-cacheable` refusal for `alloc`
and for `main`. These are the counts of its four `cache` messages.

**Open.** None for this claim.

## Closure of the memexec key under relate

**Claim.** The set of bases that memexec uses to filter and index an entry is
closed under `Domain.relate` in the input state: `expand_inputs_with_relations`
returns a set only when one more call to `relate` adds no base. When `relate`
returns `Top`, or when no fixpoint is reached within the bound, no entry is
stored. Whether each domain reports all the relations it needs is a separate
claim, not covered here.

**Kind.** OCaml obligation.

**Symbols.** `Mem_exec.Make.expand_inputs_with_relations`,
`Mem_exec.Make.store_cacheable_call`.

**Argument.** This is the worked example of the resolution of issue #19,
checked at revision `90a4b4cc53`. The seam changed the function: it now raises
`Refused` with `relate-top` or `relate-unclosed` where it returned `Top`, and
returns the set itself on a fixpoint. The storage catches the exception and
stores nothing, as it did for `Top`. The fixpoint test, the bound of two
iterations and the use of the closed set to filter and index the entry are
unchanged.

**Evidence.** Source inspection of the changed function.

**Open.** A regression that observes the stored set after a transitive growth,
and the refusal `relate-unclosed` when the bound is exhausted, is pending.
