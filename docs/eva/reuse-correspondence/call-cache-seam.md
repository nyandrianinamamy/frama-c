# Call-cache seam

Claims about the seam between the analysis of calls and the cache of calls,
[`plugins/eva/src/engine/call_cache.ml`](../../../plugins/eva/src/engine/call_cache.ml), added by
[issue #33](https://github.com/nyandrianinamamy/frama-c/issues/33). Memexec
([`plugins/eva/src/engine/mem_exec.ml`](../../../plugins/eva/src/engine/mem_exec.ml)) is the only cache behind the seam. The
regression named in several entries is the ptests fixture
[`plugins/eva/tests/value/cache_dispositions.c`](../../../plugins/eva/tests/value/cache_dispositions.c), run in the default
configuration with the message category `cache` enabled; its oracles are
`plugins/eva/tests/value/oracle/cache_dispositions.cache.log` and
`plugins/eva/tests/value/oracle/cache_dispositions.stats.log`. The cram test
[`plugins/eva/tests/utils/call-cache.t`](../../../plugins/eva/tests/utils/call-cache.t/run.t) covers the runs with caching disabled
and with an interrupted analysis.

## The seam does not change the results of an analysis

**Claim.** Routing memexec through the seam changes no result of an analysis:
alarms, property statuses, reached statements, states and the calls answered
by memexec are those of the previous engine. Scope: every Eva configuration,
with `-eva-memexec` set or not. The message category `cache` has no verbosity
level, so its lines are printed only when `-eva-msg-key` enables it.

**Kind.** OCaml obligation.

**Depends on.** None.

**Symbols.** `Call_cache.Make.lookup`, `Call_cache.Make.store`,
`Call_cache.Make.interrupted`,
`Compute_functions.Make.compute_and_cache_call`,
`Compute_functions.Make.compute_call_with_target`,
`Mem_exec.Make.reuse_previous_call`, `Mem_exec.Make.store_computed_call`,
`Call_cache.new_counter`, `Call_cache.cleanup_results`.

**Argument.** `lookup` reads `-eva-memexec` once per call, as
`compute_call_with_target` did. When it is set, `lookup` computes the argument
values before the body is analysed and calls `reuse_previous_call` with the
function, the state and these values, as `compute_and_cache_call` did. When
no entry matches, the values are returned in the `pending` value, and `store`
passes them to memexec: the option is not read again and the values are not
recomputed after the body. When the option is not set, `lookup` answers that
no entry matches without calling memexec, the body is analysed, and `store`
does not call memexec. When `-eva-memexec` was set at the lookup, `store`
calls `store_computed_call` for every result. The test on `Cacheable` moved
from `compute_and_cache_call` into that function, which refuses a result not
marked `Cacheable` before it builds anything. So an entry is inserted under
the same condition as before: the option is set and the result is marked
`Cacheable`. For such a result, `store_computed_call` performs the same operations in
the same order as before, and returns the call number or a reason instead of
`unit`. The statistics updates of memexec moved into the seam, and the
category messages are new; neither is read by the analysis. With
`-eva-no-memexec`, the seam counts nothing, as before. When an exception
leaves the analysis of a body, `compute_and_cache_call` saves its backtrace
and calls `interrupted`, which prints a message under the category and drops
any exception raised while printing, for instance by a listener of the log.
`compute_and_cache_call` then raises the first exception again with its
backtrace. An interruption received while the message is printed is dropped
in the same way; the first exception still stops the analysis. The iteration order of the lookup is unchanged. `new_counter` and `cleanup_results` are the
memexec functions, called at the same points of `Iterator` and `Analysis`.

**Evidence.** Source inspection of the change. Executed: the default Eva
ptests (`@plugins/eva/tests/ptests_config`), the ptests of every Eva
configuration (`@plugins/eva/tests/ptests`) and the native Eva tests
(`dune runtest plugins/eva`), all rerun on the changed engine. No existing
ptests oracle changed. Among the oracles that passed, those containing
`Reusing old results for call to` record hits answered through `lookup`, for
example `plugins/eva/tests/value/oracle/memexec.0.res.oracle`. The test
`plugins/eva/tests/value/split_return.i` passes `-eva-no-memexec` in each of
its runs, so its unchanged oracles cover the path where the seam answers with
no cache. A run of the fixture with `-eva-verbose 11` and without
`-eva-msg-key cache` printed no message of the category. The cram test
`call-cache.t` runs with `-eva-no-memexec` and finds no `memexec-` row in the
statistics file. Two existing cram tests print what the change adds, and
their expected outputs are updated with it: the list of message categories
(`plugins/eva/tests/utils/help-messages.t`) gains the category `cache`, and
the statistics file (`plugins/eva/tests/utils/statistics.t`) gains
`memexec-stored` rows. No analysis output differs in either test.

The [body access collector](body-access.md) can now observe a fresh body and
report its own verdict beside memexec's disposition. It leaves the order of
the memexec operations and their inputs intact. Its statistics are separate
and inactive by default. The collector's recorder is unwound before the
interrupted body is reported.

**Open.** No test compares the callbacks and their order with those of the
engine before the seam; this rests on source inspection. Equality with the
previous engine is a regression expectation on the Eva test suite, not a
proved property.

## Each refused storage has one stable reason

**Claim.** For each call whose body is analysed to completion, `store` ends in
exactly one of: an entry stored, named by its call number; or a refusal with
one reason. A call whose analysis is stopped by an exception has no storage:
its message reads `execution: interrupted; storage: none`. With
memexec, the reasons are the paths of `store_computed_call` that did not store
an entry before the seam:

| Identifier | Path |
|---|---|
| `disabled` | `-eva-memexec` is not set; memexec is not called. |
| `not-cacheable` | the result is not marked `Cacheable`. |
| `no-inout` | `Transfer_stmt.current_kf_inout` returns `None`. |
| `footprint-top` | an input or output zone given by Inout is `Top` over its blocks. |
| `relate-top` | `Domain.relate` returns `Top` during the closure of the key. |
| `relate-unclosed` | the key still grows at the third call to `Domain.relate`. |
| `exception` | `Not_found` or `Kernel_function.No_Statement` is raised while building the entry. |

The identifiers are listed by `-eva-msg-key help` and documented in
`call_cache.mli`. The seam owns the type of the reasons; `mem_exec.mli`
declares the six that memexec produces, and the seam adds `disabled`.

**Kind.** OCaml obligation.

**Depends on.** [Closure of the memexec key under
relate](#closure-of-the-memexec-key-under-relate), for the refusals
`relate-top` and `relate-unclosed`.

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
allocates, and on `main`, which calls it. Executed by `call-cache.t`:
`refused (disabled)` for every call under `-eva-no-memexec`, with both calls
to `leaf` analysed; and `interrupted` for the call stopped by
`-eva-stop-at-nth-alarm 1` and for its caller, with the same exit status and
final message as the run without the category. Also executed by
`call-cache.t`: `no-inout` for every call when the Inout plug-in is not
loaded, and `relate-top` for every call with the `printer` domain, whose
`relate` returns `Top`; in both runs the statistics count one refusal per
analysed call.

**Open.** No regression reaches `footprint-top`, `relate-unclosed` or
`exception`. For `relate-unclosed`, chains of assignments `b = a + 1;
c = b + 1; ...` analysed with the equality and octagon domains, with their
relations kept through calls, did not make the key grow for three rounds. For
`footprint-top`, writes through a pointer of unknown value did not give Inout
an unbounded set of blocks.

## A hit names the entry stored earlier

**Claim.** The entry named by a hit, `hit (entry N)`, is the entry stored by
the earlier call whose message reads `stored (entry N)`.

**Kind.** OCaml obligation.

**Depends on.** None.

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

**Depends on.** [Each refused storage has one stable
reason](#each-refused-storage-has-one-stable-reason), for the reasons counted,
and [A hit names the entry stored
earlier](#a-hit-names-the-entry-stored-earlier), for the pairing of hits and
stored entries.

**Symbols.** `Call_cache.Make.lookup`, `Call_cache.Make.store`,
`Statistics.memexec_hits`, `Statistics.memexec_misses`,
`Statistics.memexec_stored`, `Statistics.memexec_refused`.

Scope: analyses with `-eva-memexec` set. With
`-eva-no-memexec` no cache is consulted and none of these is counted, although
each message reads `refused (disabled)`.

**Argument.** `lookup` increments the hit or miss count of the called function
where it decides the lookup. `store` increments the stored or refused count
from the same value that it prints. Neither counts anything when the lookup
did not consult memexec.

**Evidence.** Executed by the fixture, from one run: one hit, one stored entry
and one miss for `leaf`; one miss and one `not-cacheable` refusal for `alloc`
and for `main`. These are the counts of its four `cache` messages. Executed
by `call-cache.t`: no `memexec-` row with `-eva-no-memexec`.

**Open.** None for this claim.

## Closure of the memexec key under relate

**Claim.** The set of blocks that memexec uses to filter and index an entry is
closed under `Domain.relate` in the input state: `expand_inputs_with_relations`
returns a set only when one more call to `relate` adds no block. When `relate`
returns `Top`, or when no fixpoint is reached within the bound, no entry is
stored. Whether each domain reports all the relations it needs is a separate
claim, not covered here.

**Kind.** OCaml obligation.

**Depends on.** None.

**Symbols.** `Mem_exec.Make.expand_inputs_with_relations`,
`Mem_exec.Make.store_cacheable_call`.

**Argument.** This is the worked example of the resolution of issue #19,
checked at revision `90a4b4cc53`. The seam changed the function: it now raises
`Refused` with `relate-top` or `relate-unclosed` where it returned `Top`, and
returns the set itself on a fixpoint. The storage catches the exception and
stores nothing, as it did for `Top`. The fixpoint test, the bound and the use
of the closed set to filter and index the entry are unchanged. The bound
starts at 2 and allows three calls to `relate`: an entry is stored when the
set stops growing at the first, second or third call, and refused with
`relate-unclosed` when the third call still adds a block.

**Evidence.** Source inspection of the changed function.

**Open.** A regression that observes the stored set after a transitive growth,
and the refusal `relate-unclosed` when the bound is exhausted, is pending.
