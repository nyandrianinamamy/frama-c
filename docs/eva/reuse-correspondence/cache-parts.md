# Parts owned by other plug-ins

A plug-in that records a result for each call registers it as a part of the
cache entries. During the fresh analysis of a body, it gives the value of
its part; the producer keeps the value with the entry; a hit of the reuse
operation restores it as the analysis of the body would have recorded it.
From and Inout register their callwise results this way
([#53](https://github.com/nyandrianinamamy/frama-c/issues/53)). The hits
concerned are those of entries supplied to the reuse operation (see
[No analysis has both caches](reuse-operation.md#no-analysis-has-both-caches));
a hit of memexec restores no part.

The fixture is
[`cache-parts.t`](../../../plugins/eva/tests/utils/cache-parts.t/run.t),
with the program
[`parts.c`](../../../plugins/eva/tests/utils/cache-parts.t/parts.c) and the
test module
[`test_cache_parts.ml`](../../../plugins/eva/tests/utils/cache-parts.t/test_cache_parts.ml).
In each scenario, a first analysis with caching disabled produces the
entries of the callees, which are supplied to a second analysis
(`Supplied_entries.supply_produced`). The callees of `parts.c` make no call;
in [`nested.c`](../../../plugins/eva/tests/utils/cache-parts.t/nested.c), a
callee calls another; in
[`dead-call.c`](../../../plugins/eva/tests/utils/cache-parts.t/dead-call.c),
the only call of a callee is on a path that its call does not take. The
programs
[`logic.c`](../../../plugins/eva/tests/utils/cache-parts.t/logic.c),
[`logic_loop.c`](../../../plugins/eva/tests/utils/cache-parts.t/logic_loop.c)
and
[`logic_wider.c`](../../../plugins/eva/tests/utils/cache-parts.t/logic_wider.c)
call a function whose assertion Eva does not evaluate.

## A part is kept with the entry of the body that gave it

**Claim.** A value given with `Cache_part.provide` during the fresh analysis
of a body called through the cache is kept with the entry produced from this
analysis when it is given for the callstack of this body, while the project
in which its analysis started is current. A value given for another
callstack or while another project is current is dropped, and the entry
lacks the part. A second value of a part replaces the first. The value is
then kept only when the key of the entry covers its reads (see [A part whose
reads the key misses is
withheld](#a-part-whose-reads-the-key-misses-is-withheld)). An entry
supplied with `Supplied_entries.supply` has no part; one supplied with
`supply_produced` has the parts of the produced entry. Both raise
`Invalid_argument` when the function of the entry is not a function of the
current project, for instance in a copy made by `Project.create_by_copy`. A
name identifies one part: registering a second part of the same name raises
`Invalid_argument`.

**Kind.** OCaml obligation.

**Depends on.** None.

**Symbols.** `Cache_part.register`, `Cache_part.capture`,
`Cache_part.provide`, `Compute_functions.Make.compute_and_cache_call`,
`Call_cache.Make.store`, `Cache_producer.Make.store`,
`Cache_entry.Make.make`, `Supplied_entries.supply_produced`,
`Supplied_entries.check_project`.

**Argument (source inspection).** In the branch of a call with no candidate,
`compute_and_cache_call` runs the analysis of the body inside
`Cache_part.capture`, which pushes a frame holding the callstack of the call
and the current project, and pops it when the analysis ends, also on an
exception (`Fun.protect`). `provide` writes into the innermost frame only,
and only when its callstack is the one given and its project is current.
The parts of the frame go to `Call_cache.Make.store`, then to the producer,
which gives them to `Cache_entry.Make.make`. The parts are values of an
extensible type, one constructor per registered part, so a value is read
back only at the type of its part (`Cache_part.find`). Since
[#47](https://github.com/nyandrianinamamy/frama-c/issues/47), a change of
the current project during the analysis of a body refuses the body itself
(`project-switch` of the collector, [Safety at a hit](safety.md)): no entry
is produced, and no entry carries a value given under another project. The
test of the project in `provide` stays as a second guard, which a stored
entry no longer reaches. The functions of a copy of a project are other
values with the same identifiers: comparing one with a function of the
original project is an internal error of the kernel. `check_project` finds
the function of the entry in the current project by its variable and
requires the same value.

**Evidence (executed).** In the scenarios `from` and `inout`, each entry
prints the parts it has: `[from, inout]` with `-calldeps`, `[inout]`
without. In the scenario `project`, the test module registers three parts
and gives values during each analysis of `copy`: one for its callstack and
one for the callstack of its caller. The entries of `copy` have
`[inout, kept]`. With `EVA_TEST_CACHE_PARTS_SWITCH`, it also gives a value
for the callstack of `copy` under another project (`Project.on`): each call
to `copy` reads `collector: refused (project-switch)`, and no entry of
`copy` is produced. Before the rebase onto #47, with the project test
removed from `provide`, the entries also had `other-project` and the
fixture failed. In the scenario `copied`, the entries produced in the
project are supplied while a copy of it is current: the supply raises
`Invalid_argument` naming `copy`. Without `check_project`, the supply
succeeds, and an analysis in the copy then stops with the internal error
`Two kf for copy (...) and copy (...)` (observed in review). In the scenario
`duplicate`, the test module registers a second part named `from`:
`Cache_part.register: a part named from is already registered`.

**Open.** From and Inout give their parts only for a call of a body that
made no call (`Callwise.provide_froms` in From,
`Operational_inputs.Callwise.provide_inout` in Inout): a hit restores the
result of the call at its own call site, not the results that the calls of
the body record at theirs. Both test the calls that the analysis of this
call recorded, not the syntax of the body. An entry of a call that made a
call can be produced ([Nested call collection](nested-calls.md)) and lacks
both parts: while the consumer of a part is enabled, the lookup rejects it
with `missing-part`, before the test that gives `nested-delivery`
([A hit within one analysis](hit.md)). An entry of a body whose calls are
all on paths that the producing call did not take has both parts; the
lookup rejects it with `nested-delivery`, the test of
[#50](https://github.com/nyandrianinamamy/frama-c/issues/50) on the syntax
of the body. Scenario `nested`, on `nested.c`, with `-calldeps`: the entries
of `inner` have `[from, inout]` and those of `outer`, which calls `inner`,
have `[]`. In the second analysis, the two calls to `inner` hit; each call
to `outer` reads `rejected (entry N: missing-part)` for the entry whose key
matches and is analysed; the callwise dependencies of the 4 call sites are
those of caching disabled. With the tests of a call without calls removed
from `provide_froms` and `provide_inout`, the entries of `outer` have
`[inout]` and the fixture fails; the From part is still withheld, since its
reads are `Top` for a call that made a call. Scenario `dead-call`, on
`dead-call.c`, with `-calldeps`: `leaf(0)` does not call `other`; the entry
of `leaf` has `[from, inout]`, its call reads `rejected (entry 1:
nested-delivery)` and is analysed, and the callwise dependencies at the 2
call sites are those of caching disabled. When #50 lifts its test on the
syntax, an entry whose body has a call that the producing call did not make
needs, for a hit, the parts of that call site or a refusal: the owners give
the result of the producing call only.

## A part whose reads the key misses is withheld

**Claim.** With the value of its part, an owner gives the blocks whose
values its computation read in the states of the call, the blocks read to
compute an address included, or `Top` when they are not known
(`Cache_part.provide ~reads`). The producer keeps a part with the entry
only when each of these blocks is in the key of the entry or is a local
variable of the body other than a formal. Otherwise the entry is stored
without the part, the trace of the category `cache-producer` reads
`stored (entry N; withheld: NAME (uncovered-read))`, and a later candidate
that lacks the part while it is needed is rejected with `missing-part`
([A candidate that lacks a needed part is
rejected](#a-candidate-that-lacks-a-needed-part-is-rejected)).

**Kind.** OCaml obligation for the check; the reads that From and Inout
give are argued by source inspection below.

**Depends on.** The producer obligations of
[Entries from fresh bodies](cache-producer.md#producer-obligations-for-exit-reuse).

**Symbols.** `Cache_part.provide`, `Cache_part.cover`,
`Cache_part.uncovered_read`, `Cache_producer.Make.store`,
`Call_cache.Make.store` (which names the parts given and not kept),
`Call_cache.report`; in From, `Callwise.reads_of_body`; in Inout,
`Operational_inputs.Callwise.reads_of` and
`Operational_inputs.Computer.unknown_logic_inputs`.

**Argument.** A hit restores the value of a part computed from the states
of the call that produced the entry. The call of the hit agrees with it on
the key only. At each statement of the body, the values of the blocks of
the key and of the locals of the body depend only on the input restricted
to the key (producer obligations). A computation that reads only such
blocks gives the same value for both calls. A formal is not counted as a
local: its value is that of the actual, which the key must hold.

The check relies on the reads that the owner gives and on the actual key of
the entry, not on the reads that the collector recorded. The key of an
entry whose call made no call contains every block that the collector
recorded as read. The key of an entry whose call made calls is reduced to
the dependencies on entry values ([Dependencies on entry
values](nested-calls.md#dependencies-on-entry-values)) and can omit a block
that a callee reads after the body overwrote it; the premise that the
values at the statements then depend only on the input restricted to the
key is open there. From and Inout give no part for a call that made a call,
so the parts kept are checked against keys of the first kind.

What the callwise computations evaluate in a body, from the source of
`From_compute` and of `Operational_inputs.Computer`, and whether Eva's
analysis of the same body reads the same blocks:

| Owner | Evaluation | Read by Eva at the statement | Reads given |
|---|---|---|---|
| From | right-hand side of an assignment and of an initializer (`find`) | yes | `expr_deps` of the expression |
| From | address of the assigned left value (`lval_to_zone_with_deps`) | yes | `address_deps` of the left value |
| From | condition of `if` and `switch`, its dependencies and its value (`transfer_guard`) | yes | `expr_deps` of the condition |
| From | returned left value (`externalize`) | yes | `expr_deps` of the returned expression |
| From | call: dependencies of the callee at the call site | no state read | `Top` at a call statement that the call reaches, nothing at one it does not reach; no part is given for a call that made a call |
| From | reachability of a statement (`Eva.Results.is_reachable`) | no state read: while the analysis runs, its results are not available and every statement is reachable | none; see [The kept part covers the skipped computation](#the-kept-part-covers-the-skipped-computation) |
| From | callbacks `Record_From_Callbacks` at the end of the call | not part of the value | none: no module of the tree registers one, and a hit does not run them |
| From, Inout | whether the results of the body are saved (`Eva.Analysis.save_results`, option `-eva-no-results-function`) | no state read: an option, the same for every call of an analysis | none; when they are not saved, the part is `Top` and reads nothing |
| From | assigns and from clauses under `-from-verify-assigns` | not part of the value | none: under this option the part is not audited, and the lookup rejects every candidate ([The From part](#the-from-part)) |
| Inout | assignment, initializer, condition, returned expression (`expr_deps`, `add_out`) | yes | the inputs |
| Inout | assertion and loop invariant (`predicate_deps` with the state at the statement) | no when tagged `no_eva`, which Eva skips; otherwise Eva reads its own locations, not checked to be the same | the logic inputs; `Top` when `predicate_deps` gives none |
| Inout | label `Pre` of an assertion (`kf_pre_state`, from `Eva.Results.at_start_of`) | no state read: while the analysis runs, the results give `Top` | the logic inputs computed in `Top`; see [The kept part covers the skipped computation](#the-kept-part-covers-the-skipped-computation) |
| Inout | label `Init` of an assertion (`Eval_terms.add_init`) | the initial state of the analysis, the same for every call | the logic inputs; see [The kept part covers the skipped computation](#the-kept-part-covers-the-skipped-computation) |
| Inout | call: result of the callee | no state read | no part is given for a call that made a call |
| Inout | reachability of a statement | the state of the call at the statement | none |

The inputs of Inout omit the blocks that the body surely wrote before
reading them; their values at the read are computed by the body from blocks
that are in the inputs. Inline assembly, `Code_annot` instructions and
`Skip` evaluate nothing. A call that made a call gives no part, so the
specifications of callees are not evaluated for a part.

The reads are not compared with the reads recorded by the collector: the
check holds when the reads of the part are in the key, whether or not Eva
read them. It replaces premise 1 of the previous version of [The kept part
covers the skipped computation](#the-kept-part-covers-the-skipped-computation),
which said that From and Inout read only blocks that Eva read. That premise
was false: Inout evaluates the assertions tagged `no_eva`.

**Evidence (executed).** Scenario `logic`, with `-calldeps` and
`-eva-slevel 20`. In `logic.c`, `leaf(p)` asserts `*p >= 0` under the tag
`no_eva` and is called with `&b`, with `&a` and through `wrap(&b)`: Eva does
not read `p`, so an entry made at `&a` matches the call at `&b`. Each entry
of `leaf` has `[from]`, the trace reads `withheld: inout (uncovered-read)`
for each entry, the candidates are rejected 9 times with `missing-part`, and
the logic inputs at the three call sites are those of caching disabled.
`logic_loop.c`, one call site visited twice: 4 rejections, equal logic
inputs. `logic_wider.c`, a call with `p` pointing to `a` or `b` then a call
with `&a`: 16 rejections with `-eva-slevel 20`, 4 without, equal logic
inputs. With `cover` keeping every part, the calls hit and the logic inputs
differ: at the three sites of `logic.c`, `a; p` where caching disabled
gives `b; p` at lines 14 and 20; in `logic_loop.c`, `a; p` where it gives
`a; b; p`; in `logic_wider.c` with `-eva-slevel 20`, `b; p` where it gives
`a; b; p` and `a; p`. These restored zones miss a block that the call
reads. Without `-eva-slevel`, the first call of `logic_wider.c` is analysed
with `p` pointing to `a` or `b`, and its entry matches the call with `&a`:
the restored zone `a; b; p` is wider than `a; p`, sound but less precise.
On `parts.c`, whose callees read only blocks of their key, every entry keeps
its parts and the calls hit.

**Open.** The reads given by From and Inout rest on the table above, by
source inspection.

## A hit restores the parts of the enabled consumers

**Claim.** At a hit of a supplied entry, after the call hooks with
`` `Reuse `` and the delivery of the Safety part and of the Reach part of
the entry, each registered part whose consumer is
enabled is restored from the entry, in the order of registration, with the
callstack of the call, the called function and the cvalue state at the
start of the call. The results hooks are not run. A hit of memexec runs the
results hooks with `` `Reuse N `` as before and restores no part.

**Kind.** OCaml obligation.

**Depends on.** [A candidate that lacks a needed part is
rejected](#a-candidate-that-lacks-a-needed-part-is-rejected).

**Symbols.** `Call_cache.Make.lookup` (`Hit` with the source
`Supplied_entry (entry, restoration)` for a supplied entry, `Legacy_trace`
for memexec), `Supplied_entries.Lookup.find`,
`Compute_functions.Make.compute_and_cache_call`, `Cache_part.restore`,
`Safety_delivery.deliver`, `Safety_delivery.delivered`,
`Body_access.without_recording`.

**Argument (source inspection).** The identifier of a supplied entry is in
none of the tables in which the consumers of `` `Reuse N `` look up a
memexec result (`MemExec` of From and of Inout). The branch of a hit
restores the parts in place of sending it when the lookup gives parts. The
restoration runs outside the observation of the collector, as the hooks of
From and Inout do in a fresh analysis (`cache_protocol:true`). It runs
before the caller finalises the call, so the result that Inout restores is
the one that the caller reads to reduce its actuals. The parts restored are
those that the lookup selected (`Cache_part.restoration`), with the answers
of the predicates of the parts that it took once, before its test of the
clients ([The restoration of a part runs audited clients
only](#the-restoration-of-a-part-runs-audited-clients-only)): the
restoration evaluates no predicate. The selection raises `Invalid_argument`
when a part of an enabled consumer is missing; the lookup has rejected such
a candidate. A restore function must return
normally: an exception stops the analysis after the writes already made by
it and by the parts restored before it, which are not undone
(`cache_part.mli`). The called function is recorded as answered by a hit
([Results computed from statement states are refused after a
hit](#results-computed-from-statement-states-are-refused-after-a-hit)).

**Evidence (executed).** The scenarios `from`, `inout` and `verify` below.
The memexec path is exercised by the default Eva tests, whose oracles do not
change.

**Open.** A plug-in outside the tree that registers a results hook gets
nothing at a hit of a supplied entry. In the tree, Eva's own hook
(`Summary.FunctionStats`) computes the statistics of a function at its
`` `Body `` results; after the restoration of the parts, the engine calls
`Safety_delivery.delivered`, through which the summary computes them again
from the tables that the delivery updated. The subscribers of these
statistics are clients of the lookup ([A hit runs no client that is not
audited](safety.md#a-hit-runs-no-client-that-is-not-audited)). The analysis
of threads rejects every candidate.

## The restoration of a part runs audited clients only

**Claim.** While a part whose consumer is enabled is not registered as
audited, the lookup rejects every supplied candidate with `callback`. The
parts of From and Inout are registered as audited. The part of Inout is
audited while every client of its hook on the inputs and outputs of each
call is: Eva's client, which reduces the actuals of the call, is registered
as audited; any other client makes the part unaudited.

**Kind.** OCaml obligation.

**Depends on.** [A hit restores the parts of the enabled
consumers](#a-hit-restores-the-parts-of-the-enabled-consumers), [A hit runs
no client that is not
audited](safety.md#a-hit-runs-no-client-that-is-not-audited).

**Symbols.** `Cache_part.register` (`audited`),
`Cache_part.decide`, `Cache_part.unaudited_clients`,
`Cache_part.restoration`, `Supplied_entries.unaudited_clients`; in
From, `Callwise.part`, `Callwise.restore_froms`; in Inout,
`Operational_inputs.Callwise.part`, `unaudited_clients`, the dynamic
functions `register_call_hook` and `register_audited_call_hook`; in Eva,
`Eva_dynamic.Inout.register_call_hook`, `Transfer_stmt.InOutCallback`.

**Argument (source inspection).** The predicates `needed` and `audited` of
the parts are client code. Each lookup with candidates evaluates them once,
with `Cache_part.decide`, before its tests of `consumer` and of the
clients, in two passes: first the predicates of the readers of the
statement states and `needed` for every registered part, then `audited`
for the parts whose `needed` holds. A lookup that rejects its candidates
with `product` evaluates none. `Cache_part.unaudited_clients` holds, by
these answers,
when a part is needed and not audited, or when a part was registered since
the answers were taken; `audited` defaults to never.
`Supplied_entries.unaudited_clients` includes it, and `find` tests it with
the other hooks, before it examines the candidates. The check of the parts
of each candidate (`missing-part`) and the selection of the parts that the
hit restores use the same answers: no predicate runs between the test and
the end of the delivery. A client that a predicate of the first pass
registers on a hook that the lookup tests, or on the hook of Inout, whose
clients the predicate `audited` of the part of Inout tests, is seen by the
audits and by the test of the same lookup; a part that it registers makes
this lookup reject its candidates with `callback`. A function `audited`
that registers a client is outside the contract: the audits asked before
it do not see the client. `cache_part.mli` states the contract of a
predicate: it returns a result, registers nothing and writes in no table of
the analysis or of the kernel.
The predicates of From and Inout read options and a flag of Inout. The
restoration of From records the dependencies in the table of the call
site, which From does not export: no client can register a hook on it.
This is the write of the analysis of the body once the dependencies are
computed, apart from its table of memexec results ([The From
part](#the-from-part)). Under `-from-verify-assigns`, the analysis of the
body also checks the assigns clauses, which evaluates terms and
predicates; the restoration does not, and the predicate `audited` of the
part answers false, so that the lookup rejects every candidate
(`callback`). The restoration of Inout
records the result in its tables, which Inout does not export, and applies
the clients of `Record_Inout_Callbacks`. Inout registers a client given to
its dynamic function `register_call_hook` as not audited, and one given to
`register_audited_call_hook` as audited. Eva registers its cell
`InOutCallback` through the second: the cell holds the result given for the
call until the caller has reduced its actuals, and is cleared after the
call ([The Inout part](#the-inout-part)); after the call of the entry
point, which has no caller, it is cleared too. No other module of the tree
registers a client.

**Evidence (executed).** Scenario `unaudited-part`: the test module
registers a part, needed in both analyses, and gives its value for every
body. Not audited, the three calls to `copy` read `callback` for each of
their three candidates (`copy: hits 0, rejected for callback 9`); audited,
the three calls hit. Scenario `inout-client`: a client registered through
`register_call_hook` gives `copy: hits 0, rejected for callback 9`. With
`Cache_part.unaudited_clients` removed from the test of the lookup (a
mutation, reverted), both scenarios give `copy: hits 3, rejected for
callback 0`. The
scenarios `from`, `inout` and `visits` hit with the parts of From and Inout
and Eva's client. Scenario `predicate`: a part never needed and not
audited, whose predicate registers a call hook of Eva at its first, then at
its second evaluation in the second analysis. At the first, the three calls
to `copy` read `callback` for each candidate (`hits 0, rejected for
callback 9`); at the second, the first call hits and the two others are
rejected (`hits 1, rejected for callback 6`). In both, the hook receives no
call with `` `Reuse ``, and the predicate runs 7 times, once for each lookup
with candidates. Before the answers were taken once, both gave `hits 1,
rejected for callback 6`, one call with `` `Reuse `` and 3 evaluations: the
predicate ran in the test, in the check of the parts and in the
restoration of the first hit.

The same scenario with `EVA_TEST_CACHE_PARTS_CLIENT=inout`: the predicate
`needed` of the part of the test, registered after those of From and Inout,
registers a client of the hook of Inout through `register_call_hook` at its
first evaluation. The three calls to `copy` read `callback` for each
candidate (`copy: hits 0, rejected for callback 9`), and the client is
called 0 times after a hit. With `EVA_TEST_CACHE_PARTS_CARRIER=reader`, the
predicate of a reader of the statement states registers the client, with
the same results. At the commit now `cbf089bcb4` (before the rebase onto #48),
where `decide` asked `audited` of each part right after its `needed`, and the
readers after the parts, both gave `copy: hits 1, rejected for callback 6`, and
the client was called 10 times after the hit. With
`EVA_TEST_CACHE_PARTS_CLIENT=part`, the predicate registers a part, never
needed, at its first evaluation: the first call to `copy` rejects its three
candidates with `callback` and the next two hit (`copy: hits 2, rejected for
callback 3`). Mutations, each applied alone to the commit now `dc06f33291`
(before the rebase onto #48) and reverted: with `decide` in one pass, the
scenario with the client of Inout registered by `needed` gives `hits 1,
rejected for callback 6` and 10 calls of the client; with the readers evaluated
after the audits, the scenario with the reader gives the same; with the count
of the parts in `Cache_part.unaudited_clients` compared with itself (the field
stays used, as warning 69 requires), the scenario with a registered part gives
`copy: hits 3, rejected for callback 0`.

## A candidate that lacks a needed part is rejected

**Claim.** A supplied candidate whose key matches the input of the call and
that lacks a part whose consumer is enabled is rejected with
`missing-part`, and the next candidate is examined; when none is used, the
body is analysed. The From part is needed when `-calldeps` is set (also by
`-from-verify-assigns`), the Inout part whenever Inout is loaded. The tests
of the key come first: a candidate whose key differs reads `key-differs`.
The test of the parts comes before the checks of
`Supplied_entries.Lookup.admit`, among them `missing-points`, which rejects
an entry without a Reach part
([Reach at a hit](reach.md#a-hit-delivers-the-reach-part-as-recorded-joins)):
a candidate that lacks both a needed part and its Reach part reads
`missing-part`. The tests of a candidate run in this order: `key-differs`,
`key-unclosed` and `missing-part` in `Cache_entry.Make.check`, then
`recursion`, `automatic-cleanup`, `watchpoint`, `hint-generation`,
`warn-categories`, `sweep`, `missing-points` and `nested-delivery` in
`admit`.

**Kind.** OCaml obligation.

**Depends on.** None.

**Symbols.** `Cache_entry.Make.check`, `Cache_part.supplies`,
`Supplied_entries.Lookup.find`, `Supplied_entries.Lookup.admit`,
`From_parameters.ForceCallDeps`, `Statistics.cache_rejected`.

**Argument (source inspection).** `check` tests the key, then its closure,
then `Cache_part.supplies`, which holds when every registered part whose
`needed` function holds is among the parts of the entry. A rejection adds
the candidate to the rejected list with its reason, as for the other two
reasons. `Lookup.find` calls `admit` only for a candidate that `check`
accepts, and `admit` tests `missing-points` after the checks of the
dependent effects and before `nested-delivery`.

**Evidence (executed).** Scenario `missing`: `-calldeps` is set after the
first analysis, whose entries have no From part. In the second analysis,
`copy` reads `rejected (entry 1: missing-part), rejected (entry 2:
key-differs), rejected (entry 3: missing-part); execution: analysed` for its
first call, the counts are 5 for `copy`, 1 for `narrow` and for
`narrow_and_write`, 4 for `checked`, and the callwise dependencies of the
three calls to `copy` are recorded. Run 3 of
[`cache_supplied.c`](../../../plugins/eva/tests/value/cache_supplied.c)
loads Inout with entries supplied by `supply`: every candidate whose key
matches reads `missing-part`. Run 4 loads From without `-calldeps`: it needs
no part, and the run is identical to run 0. Compared with the same run with
caching disabled (`-eva-no-memexec`, From loaded), the 14 statuses of the
assertions are equal, and two values are wider: `{7; 8}` against `{7}`
after `wide_first`, and `g` in `{3; 4}` against `{3}` after `loop_on_4`. This
is the precision of the entries written by hand, which run 0 shows as well
and the comment of the test expects; the results are not those of caching
disabled. With the test of `supplies`
removed, the second analysis of the scenario `missing` reaches `restore`
with a missing part and stops with exit status 125.

Scenario `both`: each entry of `copy` produced by the first analysis is
supplied again with `supply`, without its Reach part and without parts,
and Inout is loaded. The three calls to `copy` read `rejected (entry 1:
missing-part), rejected (entry 2: key-differs), rejected (entry 3:
missing-part)` and the same with the keys exchanged, and are analysed:
`copy: hits 0, rejected for missing-part 5, for missing-points 0`. With the
test of `supplies` removed from `check` (a mutation applied to
`4f20abfe60` and reverted), the same candidates read `missing-points`
(`rejected for missing-part 0, for missing-points 5`).

**Open.** None for this claim.

## The From part

**Claim.** At a hit, the callwise dependencies that From records at the call
site of the hit are joined with those kept with the entry, as the analysis
of the body joins its own. Under `-from-verify-assigns`, no call hits: the
analysis of a body checks the assigns and from clauses of the callee
against its dependencies in the state at the start of the call, a hit
evaluates nothing, and the part of From is then not audited, so that the
lookup rejects every candidate with `callback`. This is an instance of
`RecordedWrite`
([Side-table obligations](hit.md#side-table-obligations-for-skipped-work))
whose covering conjunct rests on the premise of [The kept part covers the
skipped computation](#the-kept-part-covers-the-skipped-computation).

**Kind.** OCaml obligation, with a premise argued in prose.

**Depends on.** [A hit restores the parts of the enabled
consumers](#a-hit-restores-the-parts-of-the-enabled-consumers), [The kept
part covers the skipped computation](#the-kept-part-covers-the-skipped-computation).

**Symbols.** `Callwise.restore_froms`, `Callwise.end_record`,
`Callwise.record_callwise_dependencies_in_db`, `Callwise.merge_call_froms`,
`Callwise.Tbl`, `Callwise.provide_froms`, `Eva.Logic_inout.verify_assigns`,
`Eva.Assigns.join`.

**Argument.** The instance of `RecordedWrite`: the position is the call site
of the hit (`Callstack.top_callsite`); the table is `Callwise.Tbl`, indexed by
call site, together with the table of the caller (`table_for_calls`) from
which From computes the dependencies of the caller; `saved` is the value
given by `provide_froms` when the entry was produced, after
`compute_call_from_value_states` and before the local table is popped;
`fresh` is the value that the skipped analysis would compute; `join` is
`Eva.Assigns.join`.

- `after = join before saved` at the position: `restore_froms` calls
  `end_record`, the function that records the result of an analysed body;
  it joins into `Tbl` and into the caller's table at the call site (source
  inspection).
- Other positions unchanged: `end_record` writes at the call site only. The
  memexec table of From is not written; it is read only at memexec hits,
  which an analysis with supplied entries has none of (source inspection).
- Associativity, commutativity, idempotence and the covering of both
  operands by `join`: relied on from Eva, as the join of a lattice of
  dependencies; not checked here.
- Covering `fresh`: the premise below.

`verify_assigns` takes the function, the state at the start of the call and
the dependencies, evaluates the `assumes` clauses and the assigns clauses
of the function in that state (`Eval_terms`), emits the statuses of the
clauses and prints their messages. A restoration that called it ran this
evaluation at a hit, with the kept dependencies in place of the computed
ones; it was the last evaluation of terms that a hit ran
([A hit runs no client that is not audited](safety.md#a-hit-runs-no-client-that-is-not-audited)).
`restore_froms` now only calls `end_record`. `-from-verify-assigns` sets
`-calldeps`, so the consumer of the part is enabled whenever the option
is set, and its predicate `audited` is the negation of the option: the
test of the clients that are not audited rejects every candidate, and
each body is analysed, which checks the clauses.

**Evidence (executed).** Scenario `from`: the three calls to `copy` hit; the
whole table of callwise dependencies, 10 call sites, is equal to that of the
first analysis; at line 38 it is `a FROM indirect: dst; src; direct: b`, at
line 39 `c FROM indirect: dst; src; direct: d`, and the call to `deps_main`,
whose body contains the three calls, has `a FROM direct: b; c FROM direct:
d`. Scenario `visits`, on
[`visits.c`](../../../plugins/eva/tests/utils/cache-parts.t/visits.c): the
third call to `choose` hits the entry of the first call, produced before the
second call reached the other branch; its dependencies, `a FROM indirect: c;
direct: b`, are those of caching disabled and of memexec. With
`restore_froms` reduced to nothing, the dependencies differ and the fixture
fails. Scenario `verify`, under `-from-verify-assigns`: the statuses of
the two clauses of `checked` are `VALID` after the first analysis, are
removed by a change of a correctness parameter of Eva, and are `VALID`
again after the second analysis, in which both calls to `checked` reject
their candidates (`checked: hits 0, rejected for callback 4`) and the body
is analysed. With the part audited whatever the option (a mutation, run
alone on `da5358f4c8` and reverted), both calls hit and the clauses stay
`no verification attempted`. Before this rule, both calls hit and the
restoration checked the clauses.

At a hit, From prints neither `Computing for function` nor `Done for
function` for the called function, as at a hit of memexec: these messages
come from the computation that the hit skips (known difference). In the
scenario `from`, the log holds 5 lines `Computing for function copy`: 2 from
the analysis that `-calldeps` starts, in which the third call is a hit of
memexec; 3 from the analysis with caching disabled; none from the analysis
with the three hits.

**Open.** None beyond the premise below.

## The Inout part

**Claim.** At a hit, the callwise inputs and outputs of the call kept with
the entry are recorded at the call site of the hit, for the called function
and in the table of the caller, as the analysis of the body records its
own, and they are given to Eva as the result of this call before the caller
reduces its actuals. With the parts equal to those that the analysis of the
body computes, the reduction of the actuals after the hit is that of caching
disabled.

**Kind.** OCaml obligation, with a premise argued in prose.

**Depends on.** [A hit restores the parts of the enabled
consumers](#a-hit-restores-the-parts-of-the-enabled-consumers), [The kept
part covers the skipped computation](#the-kept-part-covers-the-skipped-computation).

**Symbols.** In `Operational_inputs.Callwise`: `end_record`,
`provide_inout`, `merge_call_in_local_table`, `pop_local_table`,
`merge_call_in_global_tables`, `CallwiseResults`, `Internals`,
`Record_Inout_Callbacks`. In Eva: `Transfer_stmt.InOutCallback`,
`Transfer_stmt.Make.is_safe_argument`,
`Transfer_stmt.Make.gather_reduced_arguments`,
`Backward_formals.safe_argument`.

**Argument.** The tables are an instance of `RecordedWrite`, as for From:
the restoration calls `end_record`, the function that records the result of
an analysed body. It joins the value into the table of the caller at
(function, call site) and writes nothing else; when the analysis of the
caller ends, `pop_local_table` joins this table into `CallwiseResults` at
the same position and into `Internals` at the called function (source
inspection). The memexec table of Inout is not written.

The result given to Eva is an overwrite, which `RecordedWrite` does not
cover: `end_record` applies the callbacks, which set the cell
`InOutCallback` of Eva. Its separate argument (source inspection): the cell
is set at the end of each call, read during the finalisation of the same
call by `is_safe_argument`, and cleared when the transfer of the call ends.
The call of the entry point has no caller and no finalisation: the cell is
cleared once this call is analysed or answered by a hit, and stored
(`Compute_functions.Make.compute_main_call`), on every exit. The cell is a
state of the analysis, saved with a session: a session saved after an
analysis holds an empty cell. Before, the cell stayed filled after the call
of the entry point, analysed or answered by a hit (scenario `root`); by
source inspection, each reader of the tree reads the cell during the call
that set it, and none read the stale value. At the read, the cell holds the result
given for this call: the one of the
analysed body, or the one restored at the hit. An actual is reduced only
when the zone it depends on does not meet `over_outputs_if_termination` of
that result. The reduction is sound when this zone contains the locations
that the call may write on a path that returns, which the premise below
gives for a kept part. When the cell is empty, the syntactic criterion
`Backward_formals.safe_argument` is used.

**Evidence (executed).** Scenario `inout`: with caching disabled, `g` is
`{5}` after `narrow(g)`, which narrows its formal and does not write `g`,
and `h` is `{7}` after `narrow_and_write(h)`, which writes `h`. After the
hits, the values are the same, and the callwise inputs and outputs are equal
at the 9 call sites and for the 7 functions. With the restoration reduced to
nothing, `g` is `{-5; 5}` (the empty cell falls back to the syntactic
criterion) and the tables differ. With an empty part restored instead of the
kept one, `h` is reduced to bottom: the fixture fails, and the reduction
depends on the premise. With `-eva`, the values in the final states of the
analysed callers are those of caching disabled; see [A function with a call
answered by a hit has no final values](#a-function-with-a-call-answered-by-a-hit-has-no-final-values).
Scenario `root`, on `root.c`, whose `main` makes no call: the cell is empty
after the call of `main` analysed with caching disabled, and after the hit
of its entry in the second analysis; before the clearing, it was filled
after both.

**Open.** None beyond the premise below.

## The kept part covers the skipped computation

**Claim.** The value of a part kept with an entry covers the value that the
analysis of the body would compute at a hit, for the call of the hit: for
From, the dependencies; for Inout, the inputs and outputs. This is the
conjunct `Covers after fresh` of `RecordedWrite` for both tables, and the
soundness premise of the reduction of the actuals.

**Kind.** Argued in prose; the answers of the results of the analysis while
it runs are checked by execution.

**Depends on.** [A part whose reads the key misses is
withheld](#a-part-whose-reads-the-key-misses-is-withheld), the producer
obligations of
[Entries from fresh bodies](cache-producer.md#producer-obligations-for-exit-reuse),
among them the premise of the supplier on the options of Eva (below).

**Symbols.** `Cache_part.provide` (contract), `Callwise.reads_of_body` in
From;
`Operational_inputs.Callwise.compute_call_from_value_states` in Inout;
`Eva.Results.is_reachable`, `Eva.Results.at_start_of`, `Engine.find`,
`Self.is_computed`, `Eval_terms.add_init`.

**Argument.** From and Inout compute their parts in results hooks, from the
states of this call at the statements of the body (`before_stmts`). Premise
1: the reads that each owner gives contain every block that its computation
reads in these states. It is argued for From and Inout by the table of [A
part whose reads the key misses is
withheld](#a-part-whose-reads-the-key-misses-is-withheld); with it, a kept
part reads only blocks of the key and locals of the body, whose values at
the statements depend only on the input restricted to the key.

Premise 2: what the computations read besides the states of the call is
the same for every call. Two computations ask the results of the analysis:
From tests `Eva.Results.is_reachable` at each statement (`From_compute`),
and Inout evaluates the label `Pre` of an assertion in
`Eva.Results.at_start_of` for the callstack of the call (`kf_pre_state`).
The results are not available while the analysis runs: the analysis sets
its state to `Computing` when it starts and to `Computed` or `Aborted` when
it ends, and while `Self.is_computed` does not hold, `Engine.find` answers
`Top` for every control point (source inspection). The analysis of threads
also sets `Computed` between the analyses of two threads, outside the
results hook of any call; the collector refuses these analyses (`threaded`)
and every supplied candidate is rejected in them (`consumer`), so no part
is captured or restored there. `Eva_results` sets `Computed` when it
installs saved results, not during an analysis. An analysis started by a
callback once the state is `Computing` sets `Computed` or `Aborted` when it
ends, and the analysis that started it goes on with its results available:
the parts captured in the rest of that analysis are not covered by this
premise, and every supplied candidate is rejected there (`analysis-reset`,
[A supplied entry is used only where a hit is
supported](reuse-operation.md#a-supplied-entry-is-used-only-where-a-hit-is-supported)).
With Inout loaded, such an analysis stops with an internal error of Inout,
with or without supplied entries.
`is_reachable` then holds for every statement, and `kf_pre_state` is `Top`,
for every call of the analysis that produced the entry and of the current
one. The dataflow of From goes past the statements that the call does not
reach, where the evaluations, in the state `Bottom` of this call, read
nothing. Neither answer depends on the other calls or on their number.
The label `Init` is evaluated in the initial state of the analysis
(`Eval_terms.add_init`), the same for every call of one analysis. Between
the analysis that produced the entry and the current one, it is the same
when both start from the same initial state. Eva's own evaluation of `Init`
in the body takes this state as fixed for the analysis
([Body access](body-access.md)).

**Evidence (executed).** Scenario `history`, on
[`history.c`](../../../plugins/eva/tests/utils/cache-parts.t/history.c),
with `-calldeps`: `leaf(c)` asserts `\at(a, Pre) >= 0 && \at(a, Init) >=
0` and assigns `x` and `y` under `if (c)`; it is called with 0, 1 and 0. At
the end of each call of the analysis with caching disabled, the test module
asks the results what From and Inout ask: for the first and third calls,
the 2 statements that the call does not reach are reachable in the
results; for every call, the state at the start of `leaf` is `Top`. The
entries of `leaf` have `[from, inout]`: the label `Init` has a state
during the analysis, since a label without one gives no logic inputs
(`Eval_terms.predicate_deps`) and withholds the part. The first entry is
supplied to a second analysis, in which the first and third calls hit: the
third call restores the parts computed before the second call reached the
branch. The dependencies and the inputs and outputs at the three call
sites are those of caching disabled. With `Engine.find` answering from the
saved states during the analysis (its test of `Self.is_computed` removed),
the first call reads 0 of its 2 unreached statements as reachable in the
results, the third call 2, and the state at the start is not `Top`: the
answers depend on the earlier calls and the fixture fails. In the scenario
`visits`, the body
of `choose` is visited from three call sites and the third hit uses an
entry produced before the second visit reached the other branch: the
dependencies equal those of caching disabled and of memexec. The scenario
`logic` shows the two directions for an uncovered read, which the check
withholds.

**Open.** The argument rests on the results of Eva being unavailable while
the analysis runs, which the scenario `history` checks for the queries of
From and Inout; a later change that makes them available must revisit
premise 2. Nothing refuses the production of an entry in the rest of an
analysis after an analysis started by a callback ended in it; such an entry
is not covered when supplied to another analysis (source inspection). An
entry produced in an analysis with another initial state is not detected.
Both are premises of the supplier, stated on
`Supplied_entries.supply_produced` and in the obligations of [Entries from
fresh bodies](cache-producer.md#producer-obligations-for-exit-reuse).

The claim is stated for one configuration: the options of Eva that decide
which states are saved at the statements (`-eva-results`,
`-eva-no-results-function`) and how precisely bodies are analysed (options
of precision, of the domains and of the alarms) are equal in the analysis
that produced the entry and in the one that uses it. This is a premise of
the supplier, stated on `Supplied_entries.supply_produced` and in the
obligations of [Entries from fresh
bodies](cache-producer.md#producer-obligations-for-exit-reuse); nothing
checks it, and [#59](https://github.com/nyandrianinamamy/frama-c/issues/59),
which saves the options of the producing analysis with its entries, must
enforce it. Within one analysis these options do not change unnoticed:
each is registered as a dependency of the state of Eva's results
(`Parameters.add_dep`, `add_precision_dep`, `add_correctness_dep`), and
changing one clears the results; the lookup then rejects every candidate
with `analysis-reset` ([A supplied entry is used only where a hit is
supported](reuse-operation.md#a-supplied-entry-is-used-only-where-a-hit-is-supported)).
The options of Eva outside this registration choose the cache
(`-eva-memexec`, `-eva-cache-collect`), consolidate the results after the
analysis (`-eva-join-results`), stop the analysis (`-eva-interpreter-mode`,
`-eva-stop-at-nth-alarm`), name allocation functions, which a body with an
entry does not call (`-eva-alloc-functions`), configure the sign or traces
domains, with which every candidate is rejected (`product`), or print
messages (source inspection of `Parameters`). A violated premise can change
the restored parts and, through the reduction of the actuals, the state of
the caller. Scenario `options`, which violates the premise on purpose: with
`-eva-no-results-function narrow` in the using analysis only, `g` is `{-5;
5}` after `narrow(g)` with caching disabled and `{5}` after the hit. Two
other limits, found in review and executed again on this revision with a
test module outside the tree: with `-eva-no-results-function copy` in the
using analysis only, the dependencies at the three calls to `copy` are
`FROMTOP` with caching disabled and the finite dependencies of the
producing analysis after the three hits; in a function whose two branches
set `x` and `y` equal, a statement under `x != y` is unreachable with
`-eva-slevel 40` and reachable with `-eva-slevel 0`, and the hit of an
entry produced with `-eva-slevel 40` gives `r FROM indirect: c; direct: b
(or UNASSIGNED)` where caching disabled with `-eva-slevel 0` gives `r FROM
indirect: c; direct: a; b`. These are limits under a violated premise, not
counterexamples to the claim for one configuration.

## Readers of the states saved at statements reject every candidate

**Claim.** When the analysis computes, or a loaded plug-in reads, a result
computed from the states that Eva saves at the statements of each function,
every supplied candidate is rejected with `consumer` and the body is
analysed:

- From with `-deps`; Inout with `-out`, `-out-external`, `-input`,
  `-input-with-formals` or `-deref`;
- the plug-ins Pdg, Reduc and Studia when loaded, and every plug-in that
  loads one of them;
- the plug-ins Nonterm, Metrics, the Markdown report, WP, the constant
  propagation and Occurrence when loaded.

The test is the presence of the plug-in, not its use: a listed plug-in that
is loaded and reads nothing rejects every candidate too. The callwise
results of From and Inout are not such readers: `-calldeps` and `-inout`
leave the candidates to the examination of each one. The readers of the
tree, with the class of each, are in the table of the
[next claim](#results-computed-from-statement-states-are-refused-after-a-hit).

**Kind.** OCaml obligation.

**Depends on.** None.

**Symbols.** `Cache_part.register_state_reader`, `Cache_part.decide`,
`Cache_part.reads_statement_states`, `Cache_part.requesting_plugins`,
`Cache_part.reader_plugins`, `Cache_part.loaded_reader`,
`Supplied_entries.consumer_enabled`, `From_register` (reader `from`),
`Functionwise.To_Use`,
`Cumulative_analysis`, and the `Register` module of Inout (reader
`inout`).

**Argument (source inspection).** The results by function of From and Inout
are computed from `Eva.Results.before` at the statements of each function,
and, at a call, from the results by function of the called function. A hit
saves no state at the statements of the called function: the queries
answer the state top at the points that its body reaches
([Reach at a hit](reach.md#the-queries-see-the-points-reached-by-a-hit-with-the-state-top)),
from which these results are not those of an analysis of the body, and the
results of its callers inherit this at their calls.
`consumer_enabled` tests the presence of the plug-ins by name
(`Cache_part.loaded_reader`) and the readers declared by the options,
before any candidate is examined: the lookup evaluates the predicates of
the readers once, in the first pass of `Cache_part.decide`, with the
predicates `needed` of the parts. Pdg, Reduc and Studia depend on Inout and
request these results or read the saved states. The rule is by dependency:
Impact, Scope, Security-slicing, Slicing and Sparecode link the library of
Pdg, and loading any of them with `-no-autoload-plugins` lists Pdg among
the plug-ins (`-plugins`), so they are not named; Dive links Studia.

The six other plug-ins read `Eva.Results` at statements and conclude from
these states in a way that is not shown to be sound from the state top:
Nonterm reports a statement without a state as unreachable or
non-terminating; Metrics and the Markdown report count such statements as
not reached; WP, with its memory model based on Eva, takes the states as
hypotheses; the constant propagation replaces an expression by its value
in these states; Occurrence drops an access whose address is not precise.
They do not depend on From or Inout, and are listed by the short name
under which each registers with the kernel: `nonterm`, `metrics`, `mdr`,
`wp`, `scf`, `occurrence`. The first five were rejected at lookup before
this version, by a list in `Supplied_entries`
([A supplied entry is used only where a hit is supported](reuse-operation.md#a-supplied-entry-is-used-only-where-a-hit-is-supported));
Occurrence was not, and read the state top after a hit: at `695285889b`,
on `parts.c`, its answer for `b` in `copy` after the three hits was the
empty list, where an analysis of the bodies gives `*src` at line 11. The
names are now one value, `Cache_part.loaded_reader`: the lookup and the
refusal after a hit (next claim) read the same list.

This answers the rule of
[#47](https://github.com/nyandrianinamamy/frama-c/issues/47): a supplied
entry is rejected when a plug-in that reads Eva's states at the statements
of a skipped body is loaded. The callwise computations of From and Inout
read the states of the call being finalised (`before_stmts`), which a hit
does not have and does not need: the hit restores their result. Their
computations by function read the states of skipped bodies; they are
detected by option, not by the presence of From or Inout, which would reject
every candidate whenever either is loaded.

**Evidence (executed).** In `cache-parts.t`, scenario `readers`, run once
for each of the six options: `hits 0, rejected for consumer 15`, the 15
candidates of the 7 calls. With `-inout`: `hits 7`. With one of Pdg, Reduc,
Studia, Slicing, Dive, Occurrence, Nonterm, Metrics, the constant
propagation, WP and the Markdown report loaded and no option: `hits 0,
rejected for consumer 15`, one run for each.

Mutations, each applied alone and reverted, the test run from scratch with
`dev/cram-fresh.sh`. On `724110dfc4`: with `occurrence` removed from the
names, the run with Occurrence hits 7 times, and Occurrence loaded on the
session with hits is not refused by Eva; with `pdg` removed, the runs with
Pdg and with Slicing hit 7 times; with `studia` removed, the runs with
Studia and with Dive hit 7 times, and the server answers `getDeadCode`
after Studia is loaded. On `83cadfbf57`: with the presence of the plug-ins
dropped from `consumer_enabled`, the run with Occurrence loaded hits, then
stops with the refusal of the next claim, exit status 1. On `416e9fe167`:
with each of `nonterm`, `metrics`, `mdr`, `wp`, `scf` and `reduc` removed
alone, the run with that plug-in loaded has no rejection for `consumer` (it hits 7 times, except with Metrics, which registers a client that is not audited: the 7 calls are then rejected with `callback`), and the plug-in loaded on the session with hits is not refused: Nonterm, Metrics, the Markdown report and the constant propagation run to their end, and WP stops with an internal error, exit status 125; Reduc has no run on the session. In earlier versions, with the declared readers ignored,
the calls hit and the fixture fails; this mutation was not run again.

**Open.** The plug-ins are listed by name: a plug-in added later that reads
these states without loading a named one must be added, and nothing in the
build detects that it is missing. The list comes from a search of the
sources of the plug-ins of the tree for `Eva.` (next claim), not from an
argument that no other reader exists. Readers outside the tree are not
detected at lookup, and are not refused after the analysis unless a listed
plug-in is loaded with them. The cost of the rule is every hit of a session
in which a listed plug-in is loaded, whether or not it is used: Frama-C
loads every installed plug-in unless `-no-autoload-plugins` is given, so
that hits need this option, or an installation without these plug-ins.

## Results computed from statement states are refused after a hit

**Claim.** After an analysis in which a hit of a supplied entry answered a
call, and until an analysis without such a hit:

1. The results that From, Inout, Pdg and Studia compute from the states
   that Eva saves at statements are refused with a user error, whoever
   requests them and whenever they were computed. A request that can start
   the analysis starts it first; each request then tests whether these
   states are complete, before it computes and before it reads its table: a
   result memoised before a hit of the current analysis is refused after
   it.
2. While a plug-in of `Cache_part.loaded_reader` is loaded, the results of
   Eva refuse to give the state, the states by callstack and the callstacks
   at a statement or at the start of a function: the request stops with a
   user error that names the plug-in. The refusal is by presence, as the
   rejection at lookup
   ([previous claim](#readers-of-the-states-saved-at-statements-reject-every-candidate)):
   it stops every reader of the process, the requests of Eva's server
   included, whether or not the named plug-in is the one that asks. The
   initial state is given.
3. For a function with a call answered by a hit, Eva prints the number of
   these calls in place of its final values
   ([A function with a call answered by a hit has no final values](#a-function-with-a-call-answered-by-a-hit-has-no-final-values)).
4. With no listed plug-in loaded, the queries answer: every hit delivers
   the points that the body reaches, where the state is top
   ([Reach at a hit](reach.md#the-queries-see-the-points-reached-by-a-hit-with-the-state-top)).
   The readers that are answered are those of the class `top` in the table
   below.

The record of the functions answered by hits is saved with the session,
cleared with the results of the analysis, and kept in the results taken by
`Eva_results.get_results` and installed by `set_results`, among the
records of the hits (`Reach_delivery.records`): the four items hold in a
loaded session, in a copy of the project and for installed results.

**The readers of the tree.** One row for each reader of the states saved at
statements. The classes:

- `top`: answered after a hit, with the state top at the points of the
  hit. The row says why the answer is sound.
- `refused`: stops with a user error after a hit.
- `consumer`: its presence, or its option, rejects every supplied entry at
  lookup, so that no hit occurs in an analysis run while it is enabled.
- `none`: reads no state saved at a statement.

A reader can be `consumer` and `refused`: the second covers a reader loaded
or enabled after the hits, in the same process or on a loaded session. The
column *Decided at* gives the lines that decide the class. The last column
says what the state queries of
[#49](https://github.com/nyandrianinamamy/frama-c/issues/49) change:
`candidate` marks a refusal whose only reason is the missing states, which
can be lifted once the reader is shown to compute a sound result from
states that cover the visits of the hits without being those of an
analysis of the body. The rows marked *new* change class in this version;
*new refusal* marks a reader that was `consumer` before it and is now also
`refused` when it is loaded after the hits.

Readers inside Eva:

| # | Reader | Class | Decided at | Test | With #49 |
|---|---|---|---|---|---|
| 1 | The queries at a statement or at the start of a function, with no listed plug-in loaded: `Eva.Results` (`before`, `after`, `at_start_of`, `in_callstack`, `callstacks`, `is_reachable`, and the evaluations on their answers), and the requests `get_state`, `get_state_by_callstack` and `callstacks` of the engine | `top`: the state is top on the callstack of a hit and over all callstacks at a point that a hit reaches; an evaluation in the top state covers every state of the visit | `engine.ml:68` and `:73` | `raw`; `late-reader`, lines `after the hits`; `cache-reach.t`, `loop.c` | the states of the visit in place of top |
| 2 | The same queries while a plug-in of `loaded_reader` is loaded (*new*) | `refused` | `engine.ml:172`, `:177`, `:192`; `safety_delivery.ml:44` | `late-reader`, lines `with a reader loaded`, `in a copy`, `results with hits installed`, `in a copy of the installed results` | `candidate`, plug-in by plug-in (rows 22 to 31) |
| 3 | The final values of a function, printed with `-eva` (`Cvalue_domain.display_final_state`); reads the store of the cvalue domain, without the engine (*new*) | `refused` for a function with a hit: prints the number of its hits | `cvalue_domain.ml:459` | `inout` with `-eva`; `saved-states`; `cache-reach.t`, `loop.c` | not enough: the printer reads the store, which #49 does not fill |
| 4 | The filter of the final values by the outputs of Inout (`Eva_dynamic.Inout.kf_outputs`) | `top`: answers `Top`, and the values are printed unfiltered | `eva_dynamic.ml:26` | `inout` with `-eva`, lines `Cannot filter` | follows row 17 |
| 5 | The marking of dead code (`Eval_annots.mark_unreachable`) and the coverage of the summary (`Summary`) | `top`: read whether a statement is reached, and the points of the hits are reached | `eval_annots.ml:56`, `:67`, `:107`; `summary.ml:179`, `:276` | `cache-reach.t`, `reach.c`; `cache-safety.t`, `passes.c` | no change |
| 6 | The refinement of the statuses of the alarms (`Eval_annots.mark_green_and_red`) and `Export` | `top`: conclude at a statement only when every callstack agrees, and the state is top on the callstacks of the hits ([The passes after the analysis read the points reached by hits](reach.md#the-passes-after-the-analysis-read-the-points-reached-by-hits)) | `eval_annots.ml:124`, `:141`; `export.ml:219` to `:231` | `cache-safety.t`, `passes.c`; `cache-reach.t`, `reach.c` | more statuses refined |
| 7 | The server request `getDeadCode` | `top`, as row 5; `refused` while a listed plug-in is loaded (row 2, *new*) | `ast_requests.ml:137`; `engine.ml:177` | `server`, before and after Studia is loaded | no change; row 2 |
| 8 | The other requests of Eva's server, which the graphical interface sends: the values at a statement and by callstack (`value_requests.ml:360` to `:362`, `:461`), the states before and after a statement (`analysis_requests.ml:132`) | `top`: display the state top; `refused` while a listed plug-in is loaded (row 2, *new*) | `engine.ml:68`; `engine.ml:172`, `:177` | source inspection; `raw` and `late-reader` for the queries they send | the values of the visit |
| 9 | The requests of the taint (`taint_requests.ml:164`, `:240`, `:295`) | no hit: the taint domain is a second domain, and the lookup rejects every candidate with `product` | `supplied_entries.ml:489` | [A supplied entry is used only where a hit is supported](reuse-operation.md#a-supplied-entry-is-used-only-where-a-hit-is-supported) | not concerned |
| 10 | The dependencies of a term at a statement (`Logic_inout`, installed as `Logic_deps.compute_term_deps`); its callers are Pdg, Scope, Slicing and Sparecode | `consumer` and `refused`, as row 22 | `logic_inout.ml:29`; `engine.ml:177` | as row 22 | as row 22 |
| 11 | The analysis of threads (`mt_interferences.ml:31`, `mt_shared_vars.ml:247`, `:293`) | `consumer`: enabled, it rejects every candidate | `supplied_entries.ml:238` | [A supplied entry is used only where a hit is supported](reuse-operation.md#a-supplied-entry-is-used-only-where-a-hit-is-supported) | not enough: its tables identify the calls by their analyses, not by the states |
| 12 | `Interferences.add_last_analysis` of the engine (`concurrency/interferences.ml:224`) | no caller in the tree; it asks the engine, as rows 1 and 2 | `engine.ml:172` to `:192` | none | as row 1 |
| 13 | `Eva_results.get_results` and `set_results` (`eva_results.ml:86`, `:162`): copy the states of the cvalue store | `none`: draw no conclusion; the copy carries the record of the hits | `eva_results.ml:145`, `:190` | `snapshot`; `late-reader`, lines `results with hits installed` | not concerned |
| 14 | The initial state (`Eva_results.get_initial_state`, `eval_terms.ml:209`, the request of the engine on `Initial`) | `none`: not a state at a statement | `engine.ml:170` | `late-reader`, lines `initial state` | not concerned |

Readers in the other plug-ins. The list is that of the plug-ins whose
sources name Eva: `git grep -l 'Eva\.\|open Eva\b' -- 'plugins/*.ml'
'plugins/*.mli' ':!plugins/eva'` gives files in 21 of them, all in a row
below (From and Inout in rows 15 to 20).

| # | Reader | Class | Decided at | Test | With #49 |
|---|---|---|---|---|---|
| 15 | From, dependencies by function: `From.get`, `From.compute`, `-deps`, the printers of From | `consumer` with `-deps`; `refused`, after running the analysis, before computing and before its table | `from_register.ml:159`; `functionwise.ml:33` | `readers` with `-deps`; `api`, `lazy-from`, `then`, `save`, `snapshot`, `copy` | `candidate` |
| 16 | From, callwise dependencies: `From.Callwise`, `-calldeps` | `none` for the computation: reads the states of the call being finalised; a hit restores its part. The display of `-calldeps` asks the callee of each call site (`from_register.ml:90`), in the analysed callers, whose states are saved: answered, and `refused` while a listed plug-in is loaded (row 2, *new*) | `callwise.ml` (`restore_froms`); `engine.ml:177` | `from`, `visits`; the refusal of the display was observed on a session saved with `-calldeps` and loaded with Occurrence, outside the test suite | not concerned |
| 17 | Inout by function and by statement: `kf_inputs`, `kf_outputs`, `kf_external_inputs`, `kf_external_outputs`, the inputs with formals, the dereferenced zones, `stmt_inputs`, `stmt_outputs`, `expr_inputs`; options `-input`, `-out`, `-out-external`, `-input-with-formals`, `-deref` | `consumer` with one of the options; `refused`, before computing and before its tables | `inout/src/register.ml:47`; `cumulative_analysis.ml:24`, called at `:148`, `:155`, `:163`, `inputs.ml:146`, `outputs.ml:143`, `derefs.ml:73` | `readers` with each option; `api`, `warm`, `then`, `save`, `external` | `candidate` |
| 18 | Inout, operational inputs and outputs of a function computed from its statements (`get_precise_inout` without statement, `-inout`) | `refused`, before computing and before reading the tables of a result computed from the statements | `operational_inputs.ml:208`, called at `:838`, `:852`, `:872`, `:886` | `nested`, `fallback`, `external` | `candidate` |
| 19 | Inout, operational inputs and outputs joined from the results of the calls, and callwise at a statement | `none`: a hit restores the result of its call | `operational_inputs.ml:208` (a function not computed from its statements passes) | `inout`, `fallback`, `visits` | not concerned |
| 20 | The filters `read` and `written` of Inout on the variables of the server (`Inout_requests`) | `refused`, through row 17; the server answers with an error | `cumulative_analysis.ml:24` | source inspection, no scenario | `candidate` |
| 21 | Pdg, the graph of a function: `Pdg_tbl.get`, `-fct-pdg`, `-pdg` | `consumer` by name; `refused` by its own test, after running the analysis, before computing and before its table | `cache_part.ml:143`; `pdg_tbl.ml:45` | `readers` with Pdg; `save`, then `-load` with Pdg | `candidate` |
| 22 | The reads of `Eva.Results` at statements by Pdg and by the plug-ins that load it: Impact, Scope, Security slicing, Slicing, Sparecode (*new refusal*) | `consumer` by dependency on Pdg; `refused` by row 2, since Pdg is loaded with them | `cache_part.ml:143`, `:157`; `engine.ml:172` to `:192` | `readers` with Slicing; `late-slicing`. The four others have no scenario: the rule is by dependency | `candidate` |
| 23 | Studia, the requests `getReadsLval` and `getWritesLval` | `consumer` by name; `refused` by its own test, before computing | `cache_part.ml:143`; `studia_request.ml:63`, `:84` | `readers` with Studia; `server`, lines `declaration` and `getWritesLval` | `candidate` |
| 24 | `Reads.compute` and `Writes.compute` of Studia called without its requests, as Dive does, and the reads of Dive (*new refusal*) | `consumer` by dependency on Studia; `refused` by row 17 at each statement that they examine (`Inout.stmt_inputs`, `stmt_outputs`) and by row 2 | `cache_part.ml:143`; `cumulative_analysis.ml:148` to `:163`; `engine.ml:177` | `readers` with Dive; `late-dive` | `candidate` |
| 25 | Reduc (`value2acsl.ml:149`, `:154`; `collect.ml:111`) (*new refusal*) | `consumer` by name; `refused` by row 2 and row 17 | `cache_part.ml:143`; `engine.ml:177` | `readers` with Reduc. No scenario after a hit: Reduc reads at the statements of the alarms, and the session of the test has none | `candidate` |
| 26 | Nonterm (`nonterm_run.ml:170`, `:188`, `:235`, `:276`, `:285`, `:291`) (*new refusal*) | `consumer` by name; `refused` by row 2 | `cache_part.ml:154`; `engine.ml:172` to `:192` | `readers` with Nonterm; `late-nonterm` | `candidate` |
| 27 | Metrics, coverage by Eva (`metrics_coverage.ml:205`, `:239`, `:259`) (*new refusal*) | the same | the same | `readers` with Metrics; `late-metrics` | `candidate` |
| 28 | The Markdown report, `eva-info` (`eva_info.ml:85`, `:103`) (*new refusal*) | the same | the same | `readers` with the report; `late-mdr` | `candidate` |
| 29 | WP, memory model based on Eva (`wp_eva.enabled.ml:10`) (*new refusal*) | the same | the same | `readers` with WP; `late-wp` | `candidate` |
| 30 | The constant propagation (`constant_propagation/src/api.ml:122`) (*new refusal*) | the same | the same | `readers` with it; `late-scf` | `candidate` |
| 31 | Occurrence (`occurrence/src/register.ml:95`) (*new*, at lookup and after a hit) | the same | the same | `readers` with Occurrence; `late-occurrence`; `late-reader` | `candidate` |
| 32 | Loop analysis, the bounds of a variable (`loop_analysis.ml:333`) | `top`: the value of a variable in the top state is not an integer set, `as_ival` answers an error and the plug-in gets no bound, as when Eva has no result | `loop_analysis.ml:336` to `:339`; `results.ml:624` | source inspection, no scenario | the bounds of the visit |
| 33 | Callgraph, the callers of a function (`cg.ml:196`, `Eva.Results.callsites`) | `none`: reads the table of the callers, where a hit registers the calls of the skipped body | `reach_delivery.ml:51` | `cache-reach.t`, lines `call sites` | not concerned |
| 34 | Aorai (`aorai_eva_analysis.enabled.ml:42`) | `none`: evaluates in the state that the analysis passes to its builtin | source inspection | none | not concerned |
| 35 | RTE (`rte/src/eva_analysis.enabled.ml:13`) | `none`: reads whether Eva analysed the function, and then relies on the alarms of Eva, which a hit delivers ([A hit delivers the Safety part as recorded joins](safety.md#a-hit-delivers-the-safety-part-as-recorded-joins)) | source inspection | none | not concerned |
| 36 | A reader outside the tree that asks `Eva.Results` | `top` (row 1); `refused` while a listed plug-in is loaded (row 2) | rows 1 and 2 | rows 1 and 2 | row 1 |

**Kind.** OCaml obligation.

**Depends on.**
[The queries see the points reached by a hit, with the state top](reach.md#the-queries-see-the-points-reached-by-a-hit-with-the-state-top)
for the class `top`.

**Symbols.** `Safety_delivery` (state `Eva.Safety_delivery.Skipped`, with
dependency `Self.state`; `skip_visits`, `visits_skipped`, `complete`,
`check_readers`), `Cache_part.loaded_reader`, `Engine.Make.Engine.find`,
`Engine.Make.Engine.callstacks`,
`Reach_delivery.records`, `Reach_delivery.restore`,
`Compute_functions.Make.compute_and_cache_call`,
`Eva.Results.statement_results_complete`, `Eva_results.get_results`,
`Eva_results.set_results`; `Functionwise.To_Use.memo` in From;
`Cumulative_analysis.check_statement_results`, `Inputs.get_external`,
`Outputs.get_external`, `Derefs.get_external`,
`Operational_inputs.get_internal`, `get_external`,
`get_external_with_formals`, `From_statements` and `check_from_statements`
in Inout; `Pdg_tbl.get` in Pdg; `Eva_dynamic.Inout.kf_outputs`,
`Ast_requests.dead_code`, `Reach_delivery.reached`;
`Studia_request.check_statement_results`.

**Argument (source inspection).** The branch of a hit of a supplied entry
adds the called function to the set before it delivers the Safety part and
the Reach part and restores the parts; the record of #47 and this one are
the same set. The set is a project state that
depends on the state of Eva's results: it is saved with the session, and a
new analysis clears it. `statement_results_complete` holds when it is
empty. `get_results` copies it with the other records of the hits
(`Reach_delivery.records`), and `set_results`, after clearing the results
and installing the states, alarms and statuses, restores it with them
(`Reach_delivery.restore`) before it sets the computation state to
`Computed`, which publishes the results to the hooks of this state. The
results hold this record once. A copy of the project made with a selection that
includes the dependencies of Eva's state carries it; a selection that takes
the tables of Eva's results without it would not, and no part of the tree
makes one. `Eva.Analysis.compute` is the only entry point of `Analysis`
that installs results; it starts a new analysis, which clears the set. The
tree has no function that merges the results of two analyses: one that
does must take the union of their sets.

*The refusal in the engine (item 2).* Every query of `Eva.Results` at a
statement or at the start of a function goes through three requests of the
current engine: `get_state` and `get_state_by_callstack`, both defined by
`find`, and `callstacks` (`results.ml:235`, `:238`, `:250`). `find` calls
`Safety_delivery.check_readers` for the points `Start`, `Before` and
`After`, before it reads the status of the function, so that the refusal
does not depend on the options that decide which states are saved;
`callstacks` calls it first. `check_readers` stops with a user error when
the set is not empty and `Cache_part.loaded_reader` names a plug-in. The
stores are read without the engine in three places, found with `git grep
-n 'Cvalue_results\.\|Store\.get_state\|Store\.callstacks' --
'plugins/eva/src/*.ml'`: the engine itself and the stores of the domains
that it calls; `Eva_results`, which copies the states (row 13) and reads
the initial state; and the printer of the final values (row 3). A reader
loaded after the analysis is thus refused at its first query whatever the
plug-in that asks, and the refusal needs no test in the plug-ins listed by
name.

Two plug-ins keep a test of their own, because the refusal of the engine
would not reach their user: Pdg builds a graph inside
`Build.compute_pdg`, whose handler turns a user error into a `Top` graph
that the table would keep, and Studia catches every exception in its
requests and answers that no statement accesses the zone. Their tests are
outside these handlers.

*From, Inout, Pdg and Studia (item 1).* From's `memo` runs
`Eva.Analysis.compute`, tests the set, then reads its
table; the computation of a callee's dependencies goes through the same
function. The tables of Inout by function (`Cumulative_analysis.Memo`, and
the tables `Externals` of the inputs, outputs and dereferenced zones) are
read after the test. Inout does not start the analysis for the inputs and
outputs by function or by statement: a request made before or while the
analysis runs computes from the states then available, as with caching
disabled, and every request after a hit is refused, the memoised result
included. The dereferenced zones and the operational inputs start the
analysis first. The table `Internals` of the operational inputs joins the
results of the calls, which a hit restores, and is not refused as a whole;
a function absent from it is computed from its statements after the test,
and recorded in `From_statements`, whose members are tested before
`Internals` and the two tables derived from it are read. Pdg's `get` runs
the analysis when its results are not computed, tests the set, then reads
its table. Every user of a graph in the tree goes through
`Pdg_tbl.get` (`Pdg.Api.get` and the marks of Pdg). Each refusal is a user
error naming the cause; Studia checks before computing, so
that each request is refused as a whole. `Reads.compute` and
`Writes.compute` of Studia, which Dive calls without the requests, ask
`Inout.stmt_inputs` or `Inout.stmt_outputs` at each statement that they
examine, and have no handler: a call that examines a statement stops with
the refusal of Inout, and one that examines none answers from the
operational results of Inout by function, the callers and the
initialisers, which a hit restores or does not change.

*The class `top`.* `getDeadCode`, the marking of dead code and the summary
read whether a statement is reached, which the points of the hits answer
(`Reach_delivery.reached`). Loop analysis asks the integer set of a
variable before a statement: in the top state the value of a variable is
not based on the null base, `Results.as_ival` answers `Error Top`, and the
plug-in takes no bound from Eva. No other plug-in of the tree is in this
class: each of the others either is refused, or reads no state.

While an analysis runs, `Eva.Analysis.compute` starts a whole analysis
again: its start clears the results (`Self.clear_results`), and with them
the flag that makes the function run once. A request that starts the
analysis from a callback of the analysis therefore runs a nested analysis
of the program before its test, with or without the cache, and the test
sees the hits of that analysis. The scenario `fallback` uses this from a
start hook, which runs before the analysis sets `Computing`, to memoise a
result before the hits of the analysis that goes on.

The filters `read` and `written` that Inout registers on the variables of
the server compute the inputs and outputs by function through
`Cumulative_analysis`: after hits, a request that computes them is
refused, and the server answers it with an error; no scenario sends it.
Eva's dynamic access to `kf_outputs` returns `Top` when the set is not
empty, as when Inout is not loaded, and Eva prints the final states
unfiltered. Memexec is not concerned: its hits run the results hooks.

**Evidence (executed).** All in `cache-parts.t` unless another test is
named.

*Item 1.* Scenario `api`: after the analysis in which the
three calls to `copy` hit, `From.get`, `Inout.kf_inputs`,
`Inout.stmt_inputs`, `Inout.stmt_outputs`, `Inout.expr_inputs` and the
dynamic access to `kf_outputs` are refused with the error; a later
analysis with caching disabled gives the results by function again, equal
to those of the first analysis. Scenario `lazy-from`: the first `From.get`
after the entries are supplied starts the analysis with the three hits and
is refused, as the second. Scenario `warm`:
`Inout.kf_external_inputs`, `kf_external_outputs`, `kf_inputs` and `kf_outputs`
of `copy`, requested at the start of the analysis with the supplied entries,
are computed; after the hits they are refused with the error. Scenario
`fallback`, on `nested.c`: the result of `unused`, computed at the start of
the analysis with the supplied entries in a nested analysis without hits
(`-deps` set while it runs), is refused after the hits, and that of
`inner`, joined from its calls, equals that of caching disabled. Scenario
`external`, on `nested.c`: the dereferenced zones of `inner` and the
operational inputs of `unused`, without and with its formals, whose tables
are filled at the start with `-deps`, are refused after the two hits.
Scenario `nested`: `Inout.get_precise_inout` of `unused` is computed after
caching disabled and refused after the hits. Scenario `copy`: in a copy of
the project made by `Project.create_by_copy` after the hits,
`statement_results_complete` is false and `From.get` is refused. Scenario
`snapshot`: the
results with hits, installed after those of caching disabled and again
after them, refuse `From.get`; those of caching disabled give the
dependencies of the first analysis.
Scenario `then` with `-then -deps -input`, `-then -input`, `-then
-out-external`, `-then -input-with-formals` and `-then -deref`: the error,
exit status 1, no result printed. Scenario `save`, then `-load` in another
process with `-deps`, with `-out` and with Pdg and `-fct-pdg copy`: the same
errors, exit status 1. With an
option of Eva changed after the load, the analysis runs again with caching
disabled and the graph of `copy`, with the inputs `b` and `d`, is the one of an
analysis of the program with the same options.

*Item 2.* Scenario `late-reader`: after the three hits on `copy`, the state
before and after the first statement of `copy`, the state at its start, the
states by callstack, the callstacks from `Eva.Results` and from the engine,
and the reachability of the statement are computed; once Occurrence is
loaded in the process, each is refused, in the project, in a copy of it,
with the results with hits installed again by `Eva_results.set_results`,
and in a copy of these; with the results of caching disabled installed,
each is computed; the initial state is computed in every case. On the
session saved by `save` and loaded in another process with one plug-in,
the plug-in stops at its first query with the error that names the listed
plug-in, exit status 1: Occurrence (`-occurrence`), Nonterm (`-nonterm`),
Metrics (`-metrics-eva-cover`), the constant propagation (`-scf`), WP
(`-wp -wp-model eva`), the Markdown report (`-mdr-gen md`), Slicing
(`-slice-return main`, error naming `pdg`) and Dive
(`-dive-from-variables narrow::x`, error naming `studia`).

The server requests, in their
own test module (`test_cache_parts_server.ml`), since the main one does not
load the server: after caching disabled, `getDeadCode` gives 2 reached
statements on `copy` and 4 on `narrow`, `getReadsLval` on `b` at the first call
to `copy` and on its declaration gives 4 indirect and 1 direct statements,
and `getWritesLval` 1 direct statement. After the analysis with hits in
the same process (3 hits on `copy`, 1 on `narrow`), and in the session
saved by the scenario `save` and loaded with `-load`: before Studia is
loaded, `getDeadCode` gives 2 reached statements on `copy` and 4 on
`narrow`, no unreachable one, as with caching disabled; once Studia is
loaded, `getDeadCode` on `copy` and `getReadsLval` at the call, which
locates its lvalue with the results of Eva, are refused by Eva, and
`getReadsLval` and `getWritesLval` on the declaration of `b`, which need
no state for the location, are refused by the test of Studia.

*Item 4.* Scenario `raw`: the first statement of
`copy` is reachable after caching disabled and after the hits; the value
of `src` there is `{{ &b ; &d }}` with caching disabled and
`{{ ANYTHING }}` after the hits.

*Before this version.* At `695285889b`, on `parts.c`, Occurrence loaded
after three hits on `copy` answered the empty list for `b`, `d`, `a` and
`c` in `copy`, where it answers `*src` and `*dst` at line 11 with caching
disabled; at the same revision the scenario `late-reader` does not exist,
and the eight plug-ins above are not refused. The observations at this
revision were made on its sources before the rebase onto `d11d693ddc`
(`80902ea99f`, which is not in this history and differs by documentation
and by a script of `dev/` only).

*Mutations.* Each applied alone and reverted, the test run from scratch
with `dev/cram-fresh.sh`; every one makes `cache-parts.t` fail. On
`724110dfc4`: with `check_readers` made to refuse nothing, the queries of
`late-reader` are computed with a reader loaded, Nonterm, Metrics, the
constant propagation and the Markdown report run to their end on the
session with hits, and `getDeadCode` answers after Studia is loaded; with
the call of `check_readers` removed for the point `Start`, the state at
the start of a function is computed with a reader loaded; removed for
`Before` and `After`, the states and the reachability at the statement
are; with the test of Studia removed from `compute_writes`,
`getWritesLval` answers after the hits; with the test of the dereferenced
zones removed (`derefs.ml:73`), and with that of `get_external` or of
`get_external_with_formals` removed, the request of the scenario
`external` is computed after the hits. On `83cadfbf57`: with the call of
`check_readers` removed from `callstacks`, the callstacks asked of the
engine are computed with a reader loaded; with the test of Pdg made
inert, Pdg loaded on the session prints `Top PDG` for `copy` with a
warning, exit status 0; with the test of Studia removed from
`compute_reads`, `getReadsLval` on the declaration answers 0 indirect and
0 direct statements with a warning, where caching disabled gives 4 and 1.

Earlier mutations, not run again for this version: with
`Safety_delivery.skip_visits` changed to record nothing (applied to
`4f20abfe60` and reverted), the results after the hits read as complete,
and every request refused in item 1 is computed; with the test of
`From_statements` removed, the result of `unused` in `fallback` is
returned.

**Open.**

- The refusal of item 2 is by presence. A session with hits in which a
  listed plug-in is loaded for another purpose loses the queries of Eva at
  the statements, those of Eva's own server included, until an analysis
  without hits: with Studia loaded, `getDeadCode` is refused, where it
  answers with Studia absent; a session saved with `-calldeps` and loaded
  with Occurrence stops in the display of the callwise dependencies, which
  asks the callee of each call site, before Occurrence asks anything.
  Refusing only the queries that the listed plug-in sends would need the
  identity of the caller, which the queries do not have.
- A reader that is not in the tree, and a plug-in of the tree added later,
  get the state top (row 36) unless a listed plug-in is loaded. Whether
  such a reader concludes soundly from the state top is not checked: the
  claim is for the readers of the table. Nothing in the build detects a
  reader missing from the lists.
- Rows 8, 20, 32, 34 and 35 rest on source inspection, without a scenario.
  Row 25 has no scenario after a hit, and row 22 has one for Slicing only.
- Lifting the refusals marked `candidate` needs the states at the
  statements of a skipped body (the state queries of #49, and the public
  Inner query of
  [#40](https://github.com/nyandrianinamamy/frama-c/issues/40)), and an
  argument, per reader, that its result computed from states that cover
  the visits is sound. For the readers that conclude from the absence of
  a state (Nonterm, Metrics, the Markdown report), the points of the hits
  already answer which statements are reached; no argument that these
  plug-ins use nothing else was made, and they stay refused.
- Pdg's start of the analysis before its test has no scenario that fails
  without it: Pdg loaded before an analysis rejects its candidates, so that
  a graph is requested after hits only once their analysis is computed.

## A function with a call answered by a hit has no final values

**Claim.** With `-eva`, Eva prints the final values of each analysed
function from the states that the cvalue domain saved at its statements.
For a function with a call answered by a hit in the current analysis, Eva
prints in place of the values the line `incomplete: N call(s) answered by
the cache, without a state at the statements of the function`, where N is
the count of the hits on the function. When the options say that the
states of the function are not saved (`-eva-no-results`,
`-eva-no-results-function`, `-eva-no-results-domain cvalue`), Eva prints
nothing for it, as with caching disabled. The values printed for a
function without a hit are those of caching disabled. With Inout loaded,
they are printed without the filter by the outputs of Inout, which are
refused after a hit.

**Kind.** Known difference: caching disabled prints the values, and an
analysis with a hit on the function prints that they are incomplete.

**Symbols.** `Cvalue_domain.display_final_state`, `saves_states`,
`print_incomplete_final_state`, `Safety_delivery.visits_skipped`,
`Eva_dynamic.Inout.kf_outputs`.

**Argument (source inspection).** `display_final_state` reads the store of
the cvalue domain (`Cvalue_results.get_state`), without the queries of the
engine. The state at the return statement there is the join of the states
that the analysed calls saved. A hit saves none: for a function with
analysed calls and hits, that join lacks the values of the calls answered
by the hits, and is not an over-approximation of the values at the end of
the function; for a function answered by hits only, the store has no
state. The printer tests `Safety_delivery.visits_skipped kf` before it
reads the store (`cvalue_domain.ml:459`), and prints the line with the
counter of hits of the function (`Statistics.cache_hits`). `saves_states`
repeats the conditions under which the store holds states for the function;
when one fails, caching disabled prints nothing for the function, and the
printer prints nothing either.

Eva reads the outputs by function through its dynamic access to Inout,
which gives `Top` when `statement_results_complete` is false ([Results
computed from statement states are refused after a
hit](#results-computed-from-statement-states-are-refused-after-a-hit)); the
printer then reads `Cannot filter: dumping raw memory` for the functions
that it prints.

**Evidence (executed).** In `cache-reach.t`, `loop.c` with `-eva-slevel
10`: `main` calls `body(2)`, analysed, then `body(1)`, answered by a hit,
at the same call site. With caching disabled, Eva prints `g ∈ {1; 2}` and
`out ∈ {1; 2}` at the end of `body`; with the hit, the line `incomplete: 1
call answered by the cache`. At `695285889b`, the same run printed `g ∈
{2}`, `out ∈ {2}` and `x ∈ {2}`, the values of the analysed call alone.

In `cache-parts.t`, scenario `inout` with `-eva`: Eva's own analysis and
the two analyses of the test module print a block for each of the seven
functions, three times each. After the analysis with hits, the blocks of
`checked` (2 calls), `copy` (3), `narrow` (1) and `narrow_and_write` (1)
hold the line with these counts; those of `deps_main`, `inout_main` and
`main` are unfiltered, and `g`, `h` and `out` at the end of `inout_main`
are `{5}`, `{7}` and `{5}` each time.

Scenario `saved-states`, for each of the three options, set in the
analysis that produces the entries, in the one that uses them, or in both.
With the option in the using analysis or in both, `copy` hits 3 times and
Eva prints nothing for `copy`, as the analysis with caching disabled and
the same options. With `-eva-no-results` or `-eva-no-results-function copy`
in the producing analysis alone, the 5 candidates are rejected
(`missing-points`) and the values of `copy` are those of caching disabled,
`a ∈ {1}` and `c ∈ {0; 2}`. With `-eva-no-results-domain cvalue` in the
producing analysis alone, `copy` hits 3 times and Eva prints the line. In
the nine cases, no value of `copy` is printed that caching disabled does
not print.

Mutations on `724110dfc4`, each applied alone and reverted, the tests run
from scratch. With the test of `visits_skipped` removed, `cache-reach.t`
prints `g ∈ {2}` for `body`, and `cache-parts.t` prints no block for the
four functions answered by hits. With each of the three conditions of
`saves_states` removed alone, the line is printed for `copy` under the
corresponding option in the using analysis and in both, where caching
disabled prints nothing.

**Open.** The line gives no value: a user who reads the final values of a
function loses them for every function with a hit, where an
over-approximation exists (the join of the exit states of the entries
used, restricted to their written blocks, with the states of the analysed
calls). Printing it is not done here; the printer would have to read the
states of the hits, which
[#49](https://github.com/nyandrianinamamy/frama-c/issues/49) gives to the
queries and not to the store.
