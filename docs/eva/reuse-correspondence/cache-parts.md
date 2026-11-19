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
| From | assigns and from clauses under `-from-verify-assigns` | not part of the value | none: the restoration checks them again in the state at the start of the call of the hit |
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
`` `Reuse ``, the check of the preconditions of the callee and the delivery
of the Safety part of the entry, each registered part whose consumer is
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
The predicates of From and Inout read an option and a flag of Inout. The
restoration of From checks the assigns clauses under
`-from-verify-assigns`, which emits statuses and messages whose hooks the
lookup tests, and records the dependencies in the table of the call site,
which From does not export: no client can register a hook on it. These
are the writes of the analysis of the body once the dependencies are
computed, apart from its table of memexec results ([The From
part](#the-from-part)). The restoration of Inout
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
the same results. At `cbf089bcb4` (`3f54601636` before the rebase onto #48),
where `decide` asked `audited` of each part right after its `needed`, and the
readers after the parts, both gave `copy: hits 1, rejected for callback 6`, and
the client was called 10 times after the hit. With
`EVA_TEST_CACHE_PARTS_CLIENT=part`, the predicate registers a part, never
needed, at its first evaluation: the first call to `copy` rejects its three
candidates with `callback` and the next two hit (`copy: hits 2, rejected for
callback 3`). Mutations, each applied alone to `dc06f33291` (`b37d163154`
before the rebase onto #48) and reverted: with `decide` in one pass, the
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
of the body joins its own. Under `-from-verify-assigns`, the assigns and
from clauses of the callee are checked against the kept dependencies in the
state at the start of the call, and their statuses are emitted, as after
the analysis of the body. This is an instance of `RecordedWrite`
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
the dependencies; the restoration gives it the same arguments as the
analysed body, with the kept dependencies in place of the computed ones.
Its emissions use `~distinct:true`, so the statuses of the hits are merged
with the others as those of analysed calls are.

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
fails. Scenario `verify`: the statuses of the two clauses of
`checked` are `VALID` after the first analysis, are removed by a change of a
correctness parameter of Eva, and are `VALID` again after the second
analysis, in which both calls to `checked` hit. Without the call to
`verify_assigns` in `restore_froms`, they stay `no verification attempted`
and the fixture fails.

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
analysed callers are those of caching disabled; see [A function answered by
hits only has no final state](#a-function-answered-by-hits-only-has-no-final-state).
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

**Claim.** When the analysis computes or a loaded plug-in requests a result
computed from the states that Eva saves at the statements of each function,
every supplied candidate is rejected with `consumer` and the body is
analysed: From with `-deps`; Inout with `-out`, `-out-external`, `-input`,
`-input-with-formals` or `-deref`; the plug-ins Pdg, Reduc and Studia when
loaded, and every plug-in that loads one of them. The callwise results of
From and Inout are not such readers: `-calldeps` and `-inout` leave the
candidates to the examination of each one.

**Kind.** OCaml obligation.

**Depends on.** None.

**Symbols.** `Cache_part.register_state_reader`, `Cache_part.decide`,
`Cache_part.reads_statement_states`, `Cache_part.requesting_plugins`,
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
`consumer_enabled` tests the readers declared by the options and the
presence of the plug-ins by name, before any candidate is examined: the
lookup evaluates the predicates of the readers once, in the first pass of
`Cache_part.decide`, with the predicates `needed` of the parts. Pdg,
Reduc and Studia depend on Inout and request these results or read the
saved states. The rule is by dependency: Impact, Scope, Security-slicing,
Slicing and Sparecode link the library of Pdg, and loading any of them
with `-no-autoload-plugins` lists Pdg among the plug-ins (`-plugins`), so
they are not named.

This answers the rule of
[#47](https://github.com/nyandrianinamamy/frama-c/issues/47): a supplied
entry is rejected when a plug-in that reads Eva's states at the statements
of a skipped body is loaded. The callwise computations of From and Inout
read the states of the call being finalised (`before_stmts`), which a hit
does not have and does not need: the hit restores their result. Their
computations by function read the states of skipped bodies; they are
detected by option, not by the presence of From or Inout, which would reject
every candidate whenever either is loaded.

**Evidence (executed).** Scenario `readers`, run once for each of the six
options: `hits 0, rejected for consumer 15`, the 15 candidates of the 7
calls. With `-inout`: `hits 7`. With Pdg, Reduc, Studia or Slicing loaded
and no option: `hits 0, rejected for consumer 15`. With `pdg` removed from
the names, the runs with Pdg and with Slicing hit 7 times and the fixture
fails. With the declared readers ignored, and with the list of plug-ins
emptied, the calls hit and the fixture fails.

**Open.** The plug-ins are listed by name: a plug-in added later that
requests these results without loading a named one must be added. Readers
outside the tree are not detected at lookup; a request made after the
analysis is refused (next claim).

## Results computed from statement states are refused after a hit

**Claim.** After an analysis in which a hit of a supplied entry answered a
call, the results that From, Inout, Pdg and Studia compute from the states
that Eva saves at statements are refused with a user error, whoever
requests them and whenever they were computed, until an analysis without
such a hit. A request that can start the analysis
starts it first; each request then tests whether these states are
complete, before it computes and before it reads its table: a result
memoised before a hit of the current analysis is refused after it. The
record of the functions answered by hits is saved with the session, cleared
with the results of the analysis, and kept in the results taken by
`Eva_results.get_results` and installed by `set_results`, among the
records of the hits (`Reach_delivery.records`). Every hit delivers the
points that the body reaches, where the state is top
([Reach at a hit](reach.md#the-queries-see-the-points-reached-by-a-hit-with-the-state-top)).
A reader that needs only whether a statement is reached, such as the
request `getDeadCode` of Eva's server, is not refused
([The passes after the analysis read the points reached by
hits](reach.md#the-passes-after-the-analysis-read-the-points-reached-by-hits)).
A reader of the table that needs the values at the statements stays
refused: none is shown to compute a sound result from the state top. The
readers that ask `Eva.Results` directly are not refused, and get the state
top at the points of a hit; their precision there is left to
[#49](https://github.com/nyandrianinamamy/frama-c/issues/49).

The readers, by class. The last column gives the decision for each reader
since the hits deliver the points that they reach, with the state top
([#48](https://github.com/nyandrianinamamy/frama-c/issues/48)): a reader
that computes from the values at the statements stays refused.

| Reader | Class | Witness | With the points of the hits |
|---|---|---|---|
| Dependencies by function of From: `From.get`, `From.compute`, `-deps`, the printers of From | tests before computing and before its table, after running the analysis | scenarios `api`, `lazy-from`, `then`, `save` | refused: evaluates the left and right values of each statement in the state there; computed after hits, it differs from the result of caching disabled (scenario `snapshot` under the mutation of `skip_visits` below) |
| Inputs and outputs of Inout by function: `Inout.kf_inputs`, `kf_outputs`, `kf_external_inputs`, `kf_external_outputs`, the inputs with formals, the dereferenced zones; options `-input`, `-out`, `-out-external`, `-input-with-formals`, `-deref` | tests before computing and before its tables; `-deref` runs the analysis first | scenarios `api`, `warm`, `then`, `save` | refused: evaluates the locations of each statement in the state there |
| Inputs and outputs of Inout by statement: `stmt_inputs`, `stmt_outputs`, `expr_inputs` | tests before computing; no table | scenario `api` | refused: the same, at one statement |
| Operational inputs and outputs of Inout by function (`get_precise_inout` without statement, `-inout`), for a function computed from its statements | runs the analysis, then tests before computing; tests before reading its tables a result computed from the statements | scenarios `nested`, `fallback` | refused: the same |
| The same, for a function whose result is joined from the results of its calls | does not read statement states: a hit restores the result of its call | scenarios `inout`, `fallback` | not a reader |
| Callwise results of From and Inout: `From.Callwise`, `-calldeps`, `get_precise_inout` at a statement | does not read statement states | scenarios `from`, `inout`, `visits` | not a reader |
| Graphs of Pdg: `Pdg_tbl.get`, `-fct-pdg`, `-pdg`, and the plug-ins that get their graphs from Pdg | runs the analysis, then tests before computing and before its table | scenario `save`, then `-load` with Pdg | refused: builds the graph from the values at each statement and from the results of From |
| Requests `getReadsLval` and `getWritesLval` of Studia | tests before computing; no table | scenario `server` | refused: evaluates the zones accessed by each statement in the state there |
| Request `getDeadCode` of Eva | classifies each statement as reached or unreachable from the callstacks that reach it, those of the hits included, and skips a function of unknown reachability (`-eva-no-results-domain cvalue` only) | scenario `server` | not refused: reads whether a statement is reached; after the hits on `copy` and `narrow`, the answers equal those of caching disabled |
| Filters `read` and `written` of Inout on the variables of the server (`Inout_requests`) | test through `Cumulative_analysis`; the server answers with an error | source inspection, no scenario | refused: computes the inputs and outputs by function |
| Eva's dynamic access to `Inout.kf_outputs`, used to print the final states | does not ask Inout after a hit: `Top`, as when Inout is not loaded | scenario `inout` with `-eva` | `Top`, as before |
| `Eva.Results` at the statements of a function answered by hits, read directly: the other requests of Eva's server, such as the values at a statement; the direct reads of the plug-ins on Pdg (`Eva.Results.is_reachable`, `before`, `callee`, `condition_truth_value` and others, in Scope, Sparecode, Impact, Slicing and Security slicing) and of Studia's `Reads.compute` and `Writes.compute` (`Eva.Results.callee`, `callsites`), called directly as Dive does; the other plug-ins of the tree whose sources call `Eva.Results` (Aorai, Callgraph, Constant propagation, Dive, Loop analysis, Markdown report, Metrics, Nonterm, Occurrence, Reduc, Wp); the plug-ins of #47 loaded after the analysis; the graphical interface. The list comes from a search of the sources for `Eva.Results.`, not from an argument that no other reader exists | not refused | scenario `raw` | the points of the hits are reachable, with the state top; the precision of each reader there is left to [#49](https://github.com/nyandrianinamamy/frama-c/issues/49) |

**Kind.** OCaml obligation.

**Depends on.** None.

**Symbols.** `Safety_delivery` (state `Eva.Safety_delivery.Skipped`, with
dependency `Self.state`; `skip_visits`, `visits_skipped`, `complete`),
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

From's `memo` runs `Eva.Analysis.compute`, tests the set, then reads its
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
its table; the graph is built inside `Build.compute_pdg`, whose handler
turns a user error into a `Top` graph that the table would keep, so the
test is outside it. Every user of a graph in the tree goes through
`Pdg_tbl.get` (`Pdg.Api.get` and the marks of Pdg). Each refusal is a user error naming the cause; Studia
catches every exception in its requests and checks before computing, so
that each request is refused as a whole. `getDeadCode` does not test the
set: it reads whether a statement is reached, which the points of the hits
answer (`Reach_delivery.reached`).

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

**Evidence (executed).** Scenario `api`: after the analysis in which the
three calls to `copy` hit, `From.get`, `Inout.kf_inputs`,
`Inout.stmt_inputs`, `Inout.stmt_outputs`, `Inout.expr_inputs` and the
dynamic access to `kf_outputs` are refused with the error; a later
analysis with caching disabled gives the results by function again, equal
to those of the first analysis. Scenario `lazy-from`: the first `From.get`
after the entries are supplied starts the analysis with the three hits and
is refused, as the second; before the change, it returned `FROMUNREACHABLE`
for `copy` and memoised it. Scenario `warm`: `Inout.kf_external_inputs`,
`kf_external_outputs`, `kf_inputs` and `kf_outputs` of `copy`, requested
at the start of the analysis with the supplied entries, are computed; after
the hits they are refused with the error; before the change, the first two
returned their memoised result. Scenario
`fallback`, on `nested.c`: the result of `unused`, computed at the start of
the analysis with the supplied entries in a nested analysis without hits
(`-deps` set while it runs), is refused after the hits, and that of
`inner`, joined from its calls, equals that of caching disabled; with the
test of `From_statements` removed, the result of `unused` is returned.
Scenario `nested`: `Inout.get_precise_inout` of `unused` is computed after
caching disabled and refused after the hits. Scenario `copy`: in a copy of
the project made by `Project.create_by_copy` after the hits,
`statement_results_complete` is false and `From.get` is refused. Scenario
`snapshot`: the
results with hits, installed after those of caching disabled and again
after them, refuse `From.get`; those of caching disabled give the
dependencies of the first analysis; before the change, the results with
hits were installed as complete and `From.get` gave `FROMUNREACHABLE`.
Scenario `then` with `-then -deps -input`, `-then -input`, `-then
-out-external`, `-then -input-with-formals` and `-then -deref`: the error,
exit status 1, no result printed. Scenario `save`, then `-load` in another
process with `-deps`, with `-out` and with Pdg and `-fct-pdg copy`: the same
errors, exit status 1; before the change, Pdg warned `unreachable entry
point` and printed a bottom graph for `copy`. With an option of Eva changed
after the load, the analysis runs again with caching disabled and the
graph of `copy`, with the inputs `b` and `d`, is the one of an analysis of
the program with the same options. The server requests, in their own test
module (`test_cache_parts_server.ml`), since the main one does not load the
server: after caching disabled, `getDeadCode` gives 2 reached statements
on `copy` and 4 on `narrow`, `getReadsLval` on `b` at the first call to
`copy` gives 4 indirect and 1 direct statements and `getWritesLval` 1
direct statement; after the analysis with hits in the same process (3 hits
on `copy`, 1 on `narrow`), and in the session saved by the scenario `save`
and loaded with `-load`, the two requests of Studia are refused, and
`getDeadCode` gives 2 reached statements on `copy` and 4 on `narrow`, no
unreachable one, as with caching disabled. Before the rebase onto #48,
`getDeadCode` answered after hits with an error naming `copy`, and before
that error with three empty lists. Scenario `raw`: the first statement of
`copy` is reachable after caching disabled and after the hits, for any
reader that asks `Eva.Results` directly; the value of `src` there is `{{ &b
; &d }}` with caching disabled and `{{ ANYTHING }}` after the hits. With
`Safety_delivery.skip_visits` changed to record nothing (a mutation applied
to `4f20abfe60` and reverted), the results after the hits read as
complete, and every request refused above is computed: `From.get`, the
results of Inout by function and by statement, the two requests of Studia,
the options of the scenarios `then` and `save`, and the graph of `copy` on
the loaded session; the results with hits installed by `set_results` give
`From.get` a result that differs from that of the first analysis. With the
check of
Studia removed, Studia warns `Error when computing reads` and answers with
no statement.

**Open.** The readers of the last row of the table are not refused: they
get the state top at the points of a hit, and none of them is checked
here beyond the scenario `raw`; their precision there is left to
[#49](https://github.com/nyandrianinamamy/frama-c/issues/49). Lifting the
refusals of the other rows needs the states at the statements of a skipped
body (the state queries of #49, and the public Inner query of
[#40](https://github.com/nyandrianinamamy/frama-c/issues/40)), or an
argument, per reader, that its result computed from the state top covers
the result of an analysis of the body. The test of
the dereferenced zones before their table, and Pdg's start of the analysis
before its test, have no scenario that fails without them: the zones are
computed only for `-deref`, which rejects every candidate during the
analysis, and Pdg loaded before an analysis rejects its candidates, so that
a graph is requested after hits only once their analysis is computed.

## A function answered by hits only has no final state

**Claim.** With `-eva` and Inout loaded, Eva prints the final state of each
analysed function, filtered by the outputs that Inout computes by function.
After hits, these outputs are refused, and Eva prints the final states
unfiltered; the values of an analysed caller are those of caching disabled.
A function whose calls are all answered by hits is not printed.

**Kind.** Known difference.

**Argument (source inspection).** Eva reads the outputs by function through
its dynamic access to Inout, which gives `Top` when
`statement_results_complete` is false ([Results computed from statement
states are refused after a
hit](#results-computed-from-statement-states-are-refused-after-a-hit)); the
printer then reads `Cannot filter: dumping raw memory`.
`display_final_state` prints a function only when the state before its first
statement is reachable and not top. It reads the store of the cvalue
domain (`Cvalue_results.get_state`), where no state is saved for a
function answered by hits only; the queries of Eva answer top at the points
that the hits reach (`Engine.Make_Domain.Store.get_state`), and the
printer would skip that state too.

**Evidence (executed).** Scenario `inout` with `-eva`: Eva's own analysis
and the two analyses of the test module print the final states of
`deps_main`, `inout_main` and `main` three times each; after the analysis
with hits, the three are unfiltered, and `g`, `h` and `out` at the end of
`inout_main` are `{5}`, `{7}` and `{5}` each time. Those of `copy`,
`narrow`, `narrow_and_write` and `checked`, answered by hits in the last
analysis, are printed twice.

**Open.** None for this claim.
