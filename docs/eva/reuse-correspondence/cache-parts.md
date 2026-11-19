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
(`Supplied_entries.supply_produced`). The callees make no call.

## A part is kept with the entry of the body that gave it

**Claim.** A value given with `Cache_part.provide` during the fresh analysis
of a body called through the cache is kept with the entry produced from this
analysis when it is given for the callstack of this body, while the project
in which its analysis started is current. A value given for another
callstack or while another project is current is dropped, and the entry
lacks the part. A second value of a part replaces the first. An entry
supplied with `Supplied_entries.supply` has no part; one supplied with
`supply_produced` has the parts of the produced entry.

**Kind.** OCaml obligation.

**Depends on.** None.

**Symbols.** `Cache_part.register`, `Cache_part.capture`,
`Cache_part.provide`, `Compute_functions.Make.compute_and_cache_call`,
`Call_cache.Make.store`, `Cache_producer.Make.store`,
`Cache_entry.Make.make`, `Supplied_entries.supply_produced`.

**Argument (source inspection).** In the branch of a call with no candidate,
`compute_and_cache_call` runs the analysis of the body inside
`Cache_part.capture`, which pushes a frame holding the callstack of the call
and the current project, and pops it when the analysis ends, also on an
exception (`Fun.protect`). `provide` writes into the innermost frame only,
and only when its callstack is the one given and its project is current.
The parts of the frame go to `Call_cache.Make.store`, then to the producer,
which gives them to `Cache_entry.Make.make`. The parts are values of an
extensible type, one constructor per registered part, so a value is read
back only at the type of its part (`Cache_part.find`). This rule is that of
[#47](https://github.com/nyandrianinamamy/frama-c/issues/47) for its Safety
recording, at a finer grain: there, a change of project during the
recording refuses the whole recording; here, only the value given under the
other project is dropped.

**Evidence (executed).** In the scenarios `from` and `inout`, each entry
prints the parts it has: `[from, inout]` with `-calldeps`, `[inout]`
without. In the scenario `project`, the test module registers three parts
and gives a value of each during each analysis of `copy`: for its callstack,
for its callstack under another project (`Project.on`), and for the
callstack of its caller. The entries of `copy` have `[inout, kept]`. With the
project test removed from `provide`, they also have `other-project` and the
fixture fails.

**Open.** From and Inout give their parts only for a body that made no call
(`Callwise.provide_froms` in From, `Operational_inputs.Callwise.provide_inout`
in Inout): a hit restores the
result of the call at its own call site, not the results that the calls of
the body record at theirs. No entry is produced today for a body with a
call: the collector refuses it. This restriction has no regression.

## A hit restores the parts of the enabled consumers

**Claim.** At a hit of a supplied entry, after the call hooks with
`` `Reuse `` and the check of the preconditions of the callee, each
registered part whose consumer is enabled is restored from the entry, in
the order of registration, with the callstack of the call, the called
function and the cvalue state at the start of the call. The results hooks
are not run. A hit of memexec runs the results hooks with `` `Reuse N `` as
before and restores no part.

**Kind.** OCaml obligation.

**Depends on.** [A candidate that lacks a needed part is
rejected](#a-candidate-that-lacks-a-needed-part-is-rejected).

**Symbols.** `Call_cache.Make.lookup` (`Hit` with `Some parts` for a
supplied entry, `None` for memexec), `Supplied_entries.Lookup.find`,
`Compute_functions.Make.compute_and_cache_call`, `Cache_part.restore`,
`Body_access.without_recording`.

**Argument (source inspection).** The identifier of a supplied entry is in
none of the tables in which the consumers of `` `Reuse N `` look up a
memexec result (`MemExec` of From and of Inout). The branch of a hit
restores the parts in place of sending it when the lookup gives parts. The
restoration runs outside the observation of the collector, as the hooks of
From and Inout do in a fresh analysis (`cache_protocol:true`). It runs
before the caller finalises the call, so the result that Inout restores is
the one that the caller reads to reduce its actuals. `restore` raises
`Invalid_argument` when a part of an enabled consumer is missing; the
lookup has rejected such a candidate.

**Evidence (executed).** The scenarios `from`, `inout` and `verify` below.
The memexec path is exercised by the default Eva tests, whose oracles do not
change.

**Open.** A plug-in outside the tree that registers a results hook gets
nothing at a hit of a supplied entry. In the tree, Eva's own hook
(`Summary.FunctionStats`) ignores `` `Reuse ``, and the analysis of threads
rejects every candidate.

## A candidate that lacks a needed part is rejected

**Claim.** A supplied candidate whose key matches the input of the call and
that lacks a part whose consumer is enabled is rejected with
`missing-part`, and the next candidate is examined; when none is used, the
body is analysed. The From part is needed when `-calldeps` is set (also by
`-from-verify-assigns`), the Inout part whenever Inout is loaded. The tests
of the key come first: a candidate whose key differs reads `key-differs`.

**Kind.** OCaml obligation.

**Depends on.** None.

**Symbols.** `Cache_entry.Make.check`, `Cache_part.supplies`,
`From_parameters.ForceCallDeps`, `Statistics.cache_rejected`.

**Argument (source inspection).** `check` tests the key, then its closure,
then `Cache_part.supplies`, which holds when every registered part whose
`needed` function holds is among the parts of the entry. A rejection adds
the candidate to the rejected list with its reason, as for the other two
reasons.

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
no part, and the run is identical to run 0. With the test of `supplies`
removed, the second analysis of the scenario `missing` reaches `restore`
with a missing part and stops with exit status 125.

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
d`. With `restore_froms` reduced to nothing, the dependencies differ and the
fixture fails. Scenario `verify`: the statuses of the two clauses of
`checked` are `VALID` after the first analysis, are removed by a change of a
correctness parameter of Eva, and are `VALID` again after the second
analysis, in which both calls to `checked` hit. Without the call to
`verify_assigns` in `restore_froms`, they stay `no verification attempted`
and the fixture fails.

**Open.** The premise below. The fixture has one visit of each callstack.

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
At the read, the cell holds the result given for this call: the one of the
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
depends on the premise. With `-eva`, the final states of the analysed
callers are those of caching disabled; see [A function answered by hits only
has no final state](#a-function-answered-by-hits-only-has-no-final-state).

**Open.** The premise below. The fixture has one visit of each callstack.

## The kept part covers the skipped computation

**Claim.** The value of a part kept with an entry covers the value that the
analysis of the body would compute at a hit: for From, the dependencies; for
Inout, the inputs and outputs. This is the conjunct `Covers after fresh` of
`RecordedWrite` for both tables, and the soundness premise of the reduction
of the actuals.

**Kind.** Argued in prose; premises open.

**Depends on.** The producer obligations of
[Entries from fresh bodies](cache-producer.md#producer-obligations-for-exit-reuse).

**Argument.** From and Inout compute their parts in results hooks, from the
states of this call at the statements of the body (`before_stmts`). They
evaluate expressions and left values of the body in these states. The input
of a hit agrees with the input of the producer on the key, which contains
the blocks read by the body. Premise 1: the evaluations of From and Inout at
a statement read only blocks that Eva read at that statement, so their
results depend only on the states restricted to the key. The collector does
not observe these evaluations, since the hooks run outside recording, so
this premise rests on the fact that both use the evaluation functions of
`Eva.Results` on the same expressions as the transfer functions; it is not
checked. Two reads go beyond the states of the call:

- From tests `Eva.Results.is_reachable` (`From_compute`), which reads the
  states saved for every visit of the body in the current analysis, not
  only this call;
- Inout evaluates the logic inputs of an assertion with `kf_pre_state`, the
  state at the start of the function joined over the visits of the
  callstack.

When another visit adds states, the result of a fresh analysis can differ
from the kept one. Premise 2: such a difference only adds observations that
do not belong to this call. It is not established.

**Evidence.** Execution, in the cases of the fixture only: equality of the
tables of From and Inout with and without hits, with one visit of each
callstack.

**Open.** Premises 1 and 2; a regression with several visits of a callstack
or an assertion that reads the pre-state.

## Readers of the states saved at statements reject every candidate

**Claim.** When the analysis computes or a loaded plug-in requests a result
computed from the states that Eva saves at the statements of each function,
every supplied candidate is rejected with `consumer` and the body is
analysed: From with `-deps`; Inout with `-out`, `-out-external`, `-input`,
`-input-with-formals` or `-deref`; the plug-ins Pdg, Impact, Reduc, Scope,
Security-slicing, Slicing, Sparecode and Studia when loaded. The callwise
results of From and Inout are not such readers: `-calldeps` and `-inout`
leave the candidates to the examination of each one.

**Kind.** OCaml obligation.

**Depends on.** None.

**Symbols.** `Cache_part.register_state_reader`,
`Cache_part.reads_statement_states`, `Cache_part.requesting_plugins`,
`Supplied_entries.consumer_enabled`, `From_register` (reader `from`),
`Functionwise.To_Use`,
`Cumulative_analysis`, and the `Register` module of Inout (reader
`inout`).

**Argument (source inspection).** The results by function of From and Inout
are computed from `Eva.Results.before` at the statements of each function,
and, at a call, from the results by function of the called function. A hit
saves no state at the statements of the called function: the function looks
unreachable, and the results of its callers inherit this at their calls.
`consumer_enabled` tests the readers declared by the options and the
presence of the plug-ins by name, before any candidate is examined. Each of
the eight plug-ins depends on From or Inout, and requests these results or
reads the saved states.

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
calls. With `-inout`: `hits 7`. With each of the eight plug-ins loaded and
no option: `hits 0, rejected for consumer 15`. With the declared readers
ignored, and with the list of plug-ins emptied, the calls hit and the
fixture fails.

**Open.** The plug-ins are listed by name: a plug-in added later that
requests these results must be added. Readers outside the tree are not
detected.

## A request made by the supplying module is not detected

**Claim.** When the module that supplies the entries requests the results by
function of From or Inout after the analysis, with no option or plug-in of
the previous claim, these results miss the effects of the calls answered by
hits.

**Kind.** Known difference.

**Evidence (executed).** Scenario `api`: after the analysis in which the
three calls to `copy` hit, `From.get` gives `FROMUNREACHABLE` for `copy` and
for its caller `deps_main`, and `Inout.kf_inputs` gives `\nothing` for both,
where caching disabled gives `a FROM ... b; d` and `b; d; dst; src`.

**Open.** Only a test module supplies entries today. Lifting the rejection
for these readers needs the states at the statements of a skipped body,
which is the public Inner query of
[#40](https://github.com/nyandrianinamamy/frama-c/issues/40).

## A function answered by hits only has no final state

**Claim.** With `-eva` and Inout loaded, Eva prints the final state of each
analysed function, filtered by the outputs that Inout computes by function.
After hits, an analysed caller has the final state of caching disabled. A
function whose calls are all answered by hits is not printed.

**Kind.** Known difference.

**Argument (source inspection).** The outputs by function of a caller use,
at each call, the callwise result of the call (`get_external_aux ~stmt`),
which the hit restores. `display_final_state` prints a function only when
the state before its first statement is reachable; no state is saved for a
function answered by hits only.

**Evidence (executed).** Scenario `inout` with `-eva`: Eva's own analysis
and the two analyses of the test module print the final states of
`deps_main`, `inout_main` and `main` three times each, the same each time;
those of `copy`, `narrow`, `narrow_and_write` and `checked`, answered by
hits in the last analysis, twice.

**Open.** None for this claim.
