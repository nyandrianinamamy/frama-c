# Reach at a hit

Claims about the Reach part of a cache entry, added by
[issue #48](https://github.com/nyandrianinamamy/frama-c/issues/48): the
guard outcomes of the analysis of a body, the zones it reads and writes at
each statement, the call sites of the calls it makes and, when the analysis
saves the states of the body, the control points it reaches are recorded
with its entry, and a hit delivers them for its callstack. In this
version, only entries supplied by a test module reach a hit (see
[Reuse operation](reuse-operation.md)).

The modules are
[`reach_part.ml`](../../../plugins/eva/src/engine/reach_part.ml) (the
writes and their recording),
[`reach_delivery.ml`](../../../plugins/eva/src/engine/reach_delivery.ml)
(their delivery at a hit, the points reached by hits and the functions of
unknown reachability), the store of states seen by the queries,
`Engine.Make_Domain.Store` in
[`engine.ml`](../../../plugins/eva/src/engine/engine.ml), and the hit branch
of `Compute_functions.Make.compute_and_cache_call`. The results taken and
installed again by
[`eva_results.ml`](../../../plugins/eva/src/utils/eva_results.ml) hold the
records of the hits. The fixture is
[`cache-reach.t`](../../../plugins/eva/tests/utils/cache-reach.t/run.t),
with the test module `test_dead_code.ml`, which sends the server request of
dead code in a process that loads a session. As
[`cache-safety.t`](../../../plugins/eva/tests/utils/cache-safety.t/run.t)
does, it takes the entry from a first analysis of the body in the same
process, after which a change of the entry point resets the analysis, and
compares each run with the same program analysed with caching disabled.

## The Reach part records the reach of the body

**Claim.** While a body is analysed after a lookup without a hit, the
following writes are recorded, each with the calls between the body and the
write (its frames):

- each control point where Eva saves a state: the start of a called
  function, and the points before and after a statement;
- each guard outcome, the statement of a condition and the branch taken;
- the zones read and written at each statement, for each callstack;
- the call site of each call made below the body.

Each write is kept once; the zones of one statement and callstack are
joined. The producer stores these writes in the entry as its Reach part, in
two components (`Reach_part.part`): the guard outcomes, the zones and the
call sites (the joins), and the points, present only when the states of the
body are saved in the analysis, since the points reached are recorded only
then. A recording
belongs to the project that is current when it starts, as for the Safety
part
([A change of the current project refuses the recordings in progress](safety.md#a-change-of-the-current-project-refuses-the-recordings-in-progress)).

**Kind.** OCaml obligation.

**Depends on.**
[Side tables and recorded joins](body-access.md#side-tables-and-recorded-joins),
[The Safety part records the writes of the body](safety.md#the-safety-part-records-the-writes-of-the-body)
and
[Provenance, storage and lookup](cache-producer.md#provenance-storage-and-lookup).

**Symbols.** `Reach_part.capture`, `Reach_part.record_state`,
`Reach_part.record_guard`, `Reach_part.record_zones`,
`Reach_part.record_caller`, `Engine.Make_Domain.Store.register_state`,
`Iterator.add_condition`, `Iterator.record_fireable`,
`Inout_access.register`, `Function_calls.register_caller`,
`Function_calls.register_analysis_target`, `Function_calls.save_results`,
`Cache_producer.produce`, `Reach_part.part`, `Cache_entry.Make.reach`,
`Compute_functions.Make.compute_and_cache_call`.

**Argument (source inspection).** `compute_and_cache_call` runs
`Safety_part.capture` and `Body_access.capture` inside
`Reach_part.capture`, with the callstack of the call, in the branch
`No_candidate` only, and passes the writes to `Call_cache.Make.store`, which
gives them to the producer. Each table has one writer during an analysis,
and each writer records its write before it changes the table:

- the states, `Engine.Make_Domain.Store.register_state`, called by
  `Iterator.Make_Dataflow.merge_results` when the states of the function are
  saved, and by `Transfer_stmt.process_call` at the start of each called
  function, before its lookup; the initial state of the analysis, at
  `Initial`, belongs to no body and is not recorded;
- the guard outcomes, `Iterator.add_condition`, called by
  `record_fireable` for each edge of a condition with a non-empty flow;
  `Conditions_table` has no other writer;
- the zones, `Inout_access.register`, through which `register_read`,
  `register_write` and the functions of `Transfer_inout` register their
  accesses;
- the call sites, `Function_calls.register_caller`, called by
  `register_analysis_target` for each call before its lookup.

A write is recorded under the conditions of the Safety part: while the
collector observes the body (`Body_access.is_recording`), outside the checks
of the `requires` clauses of the body (`Body_access.checking_call_site`),
and in the project of the recording, or the body is refused as
`project-switch`. The frames of a write are the calls of its callstack above
the callstack of the capture; a write whose callstack does not extend it,
or a zone at a position outside a statement, refuses the body as
`side-table`. A point, a guard outcome and a call site equal to one already
recorded are not added again: the tables below join a value with itself
into the same value. The start and the call site of the body itself are
registered by the caller before the lookup, and belong to the recording of
the caller, if any. No option of the results gates the writers of the guard
outcomes, the zones and the call sites: `record_fireable`, the functions of
`Transfer_inout` and `register_analysis_target` run whether or not the
states of the body are saved. `merge_results` saves the states, and
`register_state` records the points, only when `save_results` holds for the
function (`Function_calls.save_results`): the producer gives the part its
points only then (`Cache_producer.produce`), and none otherwise. Under
`-eva-no-results-domain cvalue`, `register_state` records the point before
the store decides not to keep the state: the part has its points, and the
store has no state.

A body with calls: the part holds the writes made in the body itself, the
start and the call site of each call it makes, with the call as frame, and
the writes that a hit at such a call delivers, with the call as frame. It
holds none of the writes made in a body analysed afresh during its
analysis: `Reach_part` records a write in the innermost recording only, and
the part of each such body holds its own writes. The lookup rejects every
entry whose body contains a call (`nested-delivery`), and no hit delivers
such a part, as for the Safety part.

**Evidence (executed).** In `cache-reach.t`, the entry of `body(1)` produced
by the analysis from `producer` has 21 writes, all with empty frames: the
points before and after the seven statements reached, the then outcome of
the condition at line 8 and the else outcome of the condition at line 14,
and the zones of five statements. When the analysis from `producer` saves
no state of `body` (`-eva-no-results-function body` or `-eva-no-results`,
set by the test module for that analysis only), the part holds the two
guard outcomes and the five zones, and no points. In `loopread.c`, with
`-eva-slevel 10`, the loop of `body` reads `second`, then `first`, at
line 7: the part holds the join of the two reads, and so does the hit. In
`enclosing.c`,
the part of `parent` holds the start and the call site of `child`, with the
call of `child` as frame, and none of the writes of `child` when the
analysis of `parent` analyses `child`; when a hit answers that call, it
holds the points, the guard outcome and the zones of `child`, with the call
of `child` as frame. With the recording of the points removed from
`register_state` (a mutation, reverted), the part has no point, and the
comparison of the hit with caching disabled fails. With the read zone of a
statement replaced instead of joined (`Reach_part.record_zones`), the part
of `loopread.c` and the hit read `first; p` at line 7, where caching
disabled reads `first; second; p`. With the points given to the part
whatever the options (`Cache_producer.produce`), the entry produced without
saving the states of `body` has a part with no point, the lookup admits
it, and the statements of lines 9 and 10 are classified unreachable in the
analysis that uses it.

Over the Eva ptests with collection (`dev/collector-counts.sh`), the
collector would store 890 bodies and the producer produces 877 entries, as
before the Reach part. With the recorder disabled (a mutation of
`Reach_part.with_recorder`, reverted), every count of refusals by reason is
the same: no body is refused for its Reach part alone. On the analysis of
`tests/mopsa/cjson.t` with `-eva-slevel 4`, five runs take a median of
4.14 s and 177 MB with the recorder, and 4.06 s and 175.6 MB without it.

**Open.**

- The Reach part of a body with a call is incomplete, and no hit delivers
  it ([Composition along the observed path](nested-calls.md#composition-along-the-observed-path)).
- That these four writers are the only ones reached from a stored body is
  shown by source inspection only.

## A hit delivers the Reach part as recorded joins

**Claim.** Every hit is on a supplied entry with a Reach part. At such a
hit, when a state satisfies the preconditions of the called function, each
write of the Reach part is made again for the callstack of the hit extended
by its frames: the guard outcomes and the zones are joined with those at
their positions and the call sites are added, whatever the options that
decide which states are saved, and the points are recorded as reached in
that callstack when the states of the called function are saved in the
analysis of the hit. The lookup rejects an entry without a Reach part at
every call, and, where the states are saved, an entry whose part has no
points (`missing-points`); it then examines the next candidate, and the
function is analysed when no candidate is left. After a hit, each of the
four tables below thus equals or covers what an analysis of the body would
write there under the options of the analysis of the hit. This is an
instance of the `RecordedWrite` contract of
[Side-table obligations for skipped work](hit.md#side-table-obligations-for-skipped-work)
for the four tables below, under the premise that the saved writes are
those that an analysis of the body at the hit would make. The holders of
the addresses of locals and the end of the call are not delivered: they
are the work of the caller, after the hit as after an analysis of the body.

**Kind.** OCaml obligation. The instance of the Lean predicate
`ReuseModel.SideTables.RecordedWrite` is argued in prose; no Lean statement
is instantiated for Eva.

**Depends on.**
[The Reach part records the reach of the body](#the-reach-part-records-the-reach-of-the-body),
[A hit delivers the Safety part as recorded joins](safety.md#a-hit-delivers-the-safety-part-as-recorded-joins),
[Hit soundness](hit.md#hit-soundness) and
[The match by equality](reuse-operation.md#the-match-by-equality).

**Symbols.** `Reach_delivery.deliver`, `Reach_delivery.Points`,
`Iterator.add_condition`, `Inout_access.register`,
`Function_calls.register_caller`, `Function_calls.save_results`,
`Reach_part.reroot`, `Reach_part.part`, `Supplied_entries.reach`,
`Supplied_entries.Lookup.admit`, `Cache_entry.rejection`,
`Compute_functions.Make.compute_and_cache_call`,
`Transfer_stmt.do_one_call`, `Locals_scoping`.

**Argument (source inspection).** The parameters of `RecordedWrite` for each
table:

| Table | Position | Value | Observations represented | Join |
| --- | --- | --- | --- | --- |
| points reached by hits (`Reach_delivery.Points`) | control point, callstack | reached or not | the visits of the point in the callstack by the hits | or |
| guard outcomes (`Conditions_table` in `Iterator`) | statement of a condition | a pair of booleans, then and else | that some visit of the condition, in any callstack, takes the branch | or, on each component |
| zones (`Inout_access`) | statement, callstack | the zones read and written | the locations that the visits of the statement in the callstack may read and write | join of zones, on each component |
| call sites (`Function_calls`) | called function | the call statements of each caller | the calls of the function at these statements | union |

*Laws.* Or and union are associative, commutative and idempotent, and cover
both operands. The join of zones is the union of locations, with the same
laws.

*Replay at the position.* The hit branch of `compute_and_cache_call` calls
`Reach_delivery.deliver` after the delivery of the Safety part, with the
callstack of the call. For each write, `deliver` builds the callstack of the
hit extended by its frames (`Reach_part.reroot`). A point is added to
`Points`, a table apart from the store of states, with the union of the
callstacks of the point; the body writes the store instead, and the queries
read both
([The queries see the points reached by a hit, with the state top](#the-queries-see-the-points-reached-by-a-hit-with-the-state-top)).
The other writes go through the function that the body uses:
`Iterator.add_condition`, which sets the component of the outcome and keeps
the other, `Inout_access.register`, which joins the zones at the position,
and `Function_calls.register_caller`, which adds the call statement to those
of the caller. The guard outcomes have no callstack
in their positions, and a second delivery leaves them unchanged by
idempotence. The points, the zones and the call sites are written at the
callstack of the hit, so that each hit adds its own. The joins of the part,
its guard outcomes, zones and call sites, are written at every hit: an
analysis of the body writes them whatever the options that decide which
states are saved. Its points are written only when `save_results` holds
for the called function in the analysis of the hit
(`Function_calls.save_results`), as `merge_results` saves states only then.
A part without points comes from an analysis that saved no state of the
body: `Supplied_entries.Lookup.admit` rejects it with `missing-points` when
`save_results` holds at the call, before the check `nested-delivery`, so
that no hit leaves the statements of the body without a state in its
callstack where an analysis would save one. The four cases:

| States saved by the producer | States saved at the call | Outcome |
| --- | --- | --- |
| yes | yes | hit: joins and points delivered |
| yes | no | hit: joins delivered |
| no | yes | rejected (`missing-points`), next candidate |
| no | no | hit: joins delivered |

An entry without any Reach part, which only a test module supplies
(`Supplied_entries.supply` takes the part as an optional argument), is
rejected with `missing-points` in the four cases: a hit on it would deliver
no guard outcome, zone, call site or point. The tests of the key and of the
parts of From and Inout come before (`Cache_entry.Make.check`): a candidate
that lacks both its Reach part and a part whose consumer is enabled reads
`missing-part`
([A candidate that lacks a needed part is rejected](cache-parts.md#a-candidate-that-lacks-a-needed-part-is-rejected)).
As for every rejection, the lookup (`Cache_entry.Make.find`) then examines the
next candidate, and the function is analysed only when no candidate is left.
The hit branch of `compute_and_cache_call` thus always has a Reach part to
deliver, and `deliver` always has points when `save_results` holds. Each write
made at a hit is also recorded in the Reach part of an enclosing body under
analysis.

*Fresh contribution.* As for the Safety part: the match by equality gives a
hit only when the input of the call equals the stored input on the key, and
under the premise that the analysis of the body depends on its input through
the key only
([Producer obligations for exit reuse](cache-producer.md#producer-obligations-for-exit-reuse)),
the writes that an analysis of the body at the hit would make are the saved
writes, at the callstack of the hit. For a hand-written entry, the supplier
owes the Reach part (`Supplied_entries.supply`), and the entry gets no hit
without one.

*Other positions.* `deliver` writes at the positions of the saved writes
only. The tables it writes, `Points` and `Unknown` in `Reach_delivery`,
`Conditions_table` in `Iterator`, the table of `Inout_access` and the table
of callers of `Function_calls`, are `State_builder` tables whose modules are
not in the interfaces of their compilation units. A write runs the hooks of
change of its table, whose clients register with the `add_hook_on_change`
of the module of the table: a search of the source finds no such call for
these modules, and no client outside their compilation units can make one.
`State.add_hook_on_update`, which takes a state found by its name,
registers a hook that the project library runs when it changes the value
of the state (clear, load, copy), not at a write. No client therefore runs
at a delivery; the hooks of change of the five tables are rows "outside"
of the table of
[A hit runs no client that is not audited](safety.md#a-hit-runs-no-client-that-is-not-audited).
The observers of `Reach_part.on_result` run when a recording of a Reach
part ends, after the analysis of a body, and never at a hit. As for the
observers of the Safety part, the lookup rejects every candidate with
`callback` while one is registered without `audited`
(`Reach_part.has_unaudited_observers`).

*The holders and the end of the call.* The holders of the addresses of
locals and formals that the body writes travel with the exit states of the
entry, not as a write: the producer copies the set of holders of each exit
state (`Cache_producer`), and a hand-written entry computes it from the
state (`Supplied_entries.supply`). After the hit, as after an analysis of
the body, `Transfer_stmt.do_one_call` in the caller ends the scope of the
locals and formals of the called function, marks the values that hold
their addresses as escaping, and joins the holders into those of the
caller. The start of the hit and its call site are registered by
`Transfer_stmt.process_call` and `register_analysis_target` before the
lookup.

**Evidence (executed).** `cache-reach.t`, `reach.c`. The entry of `body(1)`
from the analysis from `producer` answers the call at line 30 of `main`;
`body(2)` at line 29 is analysed. The callstack of line 30 reaches `body`
only through the hit. After the analysis, for each statement of `body`:

- the callstacks with a state before and after it are those of caching
  disabled, the callstack of line 30 among them for the statements that
  `body(1)` reaches, and alone for those of the branch of `x == 1`
  (lines 9 and 10);
- the guard of line 8 has both outcomes, the then outcome from the hit;
- the zones of the callstack of line 30 are those of caching disabled, the
  zone of line 10 from the hit alone;
- the call sites of `body` are lines 29 and 30.

The same program analysed with caching disabled gives the same lines, and
the same lines are read after `-save` and `-load` in another process.

Prior contributions on the callstack of the hit, in `loop.c` with
`-eva-slevel 10`: `main` calls `body(2)`, analysed, then `body(1)`, a hit,
at the same call site. The hit delivers its writes on the callstack of the
analysed call: the statements and the zone of the branch of `x == 1` come
from the hit alone, the other zones and the outcomes of the condition are
joined with those of the analysed call, and the lines equal those of
caching disabled. In `twohits.c`, two hits answer the calls of lines 5
and 6, and the statements of `body` are reached in both callstacks. In
`zones.c`, `main` calls `body(2)`, analysed, then `body(1)`, a hit, at the
same call site, and the zone written at line 4 is `first; second`, also
with the collector of block accesses disabled after the entry is produced
(`COLLECT=off`), so that no body is under observation at the hit. Both
equal caching disabled.

The options that decide which states are saved, each run compared with
caching disabled under the options of the analysis that uses the entry:

- the analysis from `producer` saves no state of `body`
  (`-eva-no-results-function body` or `-eva-no-results` for that analysis
  only): the call at line 30 is rejected (`missing-points`) and analysed,
  and the lines equal those of caching disabled; the same for the entry
  supplied by hand with its part without the points;
- neither analysis saves the states of `body` (`-eva-no-results-function
  body` or `-eva-no-results` on the command line): the hit delivers its
  guard outcomes, zones and call sites and no point, and the lines equal
  those of caching disabled;
- the analysis from `producer` saves them and the analysis that uses the
  entry does not: the hit delivers no point, and the lines equal those of
  caching disabled;
- the entry supplied by hand without a Reach part (`PART=drop`), with
  the analysis that uses it saving the states of `body`, none of `body`, or
  none at all: the call at line 30 is rejected (`missing-points`) and
  analysed. Where the states are saved, the lines, the values of `x`, the
  annotations of Export, the lines after the results are taken and
  installed again and the response of `getDeadCode` on the session saved
  after that equal those of caching disabled; elsewhere, the lines equal
  those of caching disabled under the same option, the then outcome of
  the guard of line 8 and the zones of the callstack of line 30 among them.

Two candidates, in `reach.c`: the entry supplied by hand without a Reach
part, or with its part without the points, then the produced entry
(`SECOND=on`). The call at line 30 reads `rejected (entry 1:
missing-points), hit (entry 2); execution: not-analysed`, and the lines
equal those of caching disabled.

Holders. In `holder.c`, `body` stores the address of its formal into `gp`;
after the hit at line 21, `gp` holds an escaping address at the end of
`main`, as with caching disabled. In `escape.c`, `body` stores its argument,
the address of the local of its caller `mid`, into `gp`; the call of `body`
in `mid` is a hit, and after `mid` returns, `gp` holds an escaping address,
as with caching disabled: `Cvalue_domain.finalize_call` adds the holders of
the entry to those of `mid`, which `leave_scope` reads when `mid` returns.

Each of these checks fails with one change, reverted after the run:

- the points not delivered: the callstack of line 30 is missing from all
  statements, the statements of lines 9 and 10 are classified as
  unreachable, and the statement at line 9 is marked unreachable;
- the guard outcomes not delivered: the guard of line 8 has no then
  outcome;
- the zones not delivered: the callstack of line 30 has no zone;
- the call site registered in the branch `No_candidate` only instead of
  before the lookup: the call site of line 30 is missing;
- the set of callstacks of a point replaced by the latest callstack
  (`Reach_delivery.add_point`): in `twohits.c`, the statements of `body`
  are reached in the callstack of line 6 only;
- a delivered zone dropped when its position has one: in `zones.c`, the
  zone written at line 4 is `second` only;
- a delivered zone that replaces the zones at its position when no body is
  under observation (`Inout_access.register`): with `COLLECT=off`, the zone
  written at line 4 of `zones.c` is `first` only. With the collector
  enabled, `main` is under observation at the hit and the zones are
  joined: no other run fails;
- the joins delivered only with the points: when neither analysis saves the
  states of `body`, the guard of line 8 has no then outcome and the
  callstack of line 30 has no zone;
- the check `missing-points` removed for a part without points: the entry
  produced without saving the states of `body` is a hit, and the analysis
  stops with an internal error (exit status 125), from the assertion of
  `Reach_delivery.deliver` that a part has points where the states are
  saved (by source inspection);
- the points delivered whatever the options of the analysis that uses the
  entry: 14 points of `body` are recorded as reached by the hit where that
  analysis saves no state of `body` (`CONSUMER=body` and
  `CONSUMER=global`). The lines of the readers do not change: the queries
  answer `Top` at the points of a function analysed without saving its
  states, before reading the points of the hits;
- the set of holders of the produced entry left empty: `gp` holds the
  address of `x` at the end of `main` in `holder.c`, and the address of
  `local` in `escape.c`.

At `d9fbc62be5`, which admitted an entry without a Reach part, the runs
with `PART=drop` fail: the call at line 30 is a hit, the callstack of line
30 is missing from every statement, the statements of lines 9 and 10 are
classified unreachable, the guard of line 8 has no then outcome, the
callstack of line 30 has no zone, the value of `x` at line 18 is `{2}`
over all callstacks, and with `SECOND=on` the hit is on the first
candidate.

**Open.**

- The call sites of calls below the body (non-empty frames) and the start
  of a called function are delivered only by the part of a body with a
  call, which no hit delivers (`nested-delivery`, issue #50): their delivery
  is not executed. The call site of the call that a hit answers is not one
  of them: its caller registers it before the lookup
  (`register_analysis_target`), at a hit as before an analysis of the body,
  and `cache-reach.t` lists lines 29 and 30 among the call sites of `body`
  with caching enabled and disabled.
- A hit delivers no analysis status for the functions called below the
  body ([issue #51](https://github.com/nyandrianinamamy/frama-c/issues/51)).
- The frames of the delivered writes are not checked: with
  `Reach_part.reroot` changed to drop them (a mutation run on the cram tests
  of `plugins/eva/tests/utils`), no test fails, since no hit delivers a
  write with frames while the lookup rejects every body with a call
  (`nested-delivery`,
  [issue #50](https://github.com/nyandrianinamamy/frama-c/issues/50)). A
  check that fails is left to issue #51, with the delivery of the writes
  below the body.
- The Reach parts written by hand in `cache_supplied.ml`,
  `cache_supplied_keys.ml` and the precondition entry of `cache-safety.t`
  were compared once with the parts that a first analysis of each body
  records from the same input, in a run outside the test suite: they have
  the same writes, those of the precondition entry up to the numbering of
  the statements. No test repeats the comparison: a part written by hand
  that understates the writes is not caught by those ptests (with the read
  of `choice` by the condition removed from the part of
  `cache_supplied_keys.ml`, the entry still hits and the oracles are
  unchanged). These tests therefore give no evidence on the Reach part;
  `cache-reach.t`, whose parts come from a first analysis, does.

## The queries see the points reached by a hit, with the state top

**Claim.** For a control point reached by a hit in a callstack, when the
states of its function are saved in the analysis and the store of the
cvalue domain saves states, the queries of the results of Eva see that
callstack among those of the point, and answer the state top there; the
state over all callstacks is top as well. The states saved by the analysed
calls are not changed. The points reached by hits are a state of the
analysis: reset with its results, saved and loaded with a session, copied
with the project, and held by the results that `Eva_results.get_results`
takes and `Eva_results.set_results` installs again. When the states of the
function are not saved, the hit delivers no point
([A hit delivers the Reach part as recorded joins](#a-hit-delivers-the-reach-part-as-recorded-joins)).
When the store of the cvalue domain saves no state
(`-eva-no-results-domain cvalue`), the queries answer no callstack at any
point and do not see the points of the hit: the hit records its function
as of unknown reachability.

**Kind.** OCaml obligation.

**Depends on.**
[A hit delivers the Reach part as recorded joins](#a-hit-delivers-the-reach-part-as-recorded-joins).

**Symbols.** `Engine.Make_Domain.Store.get_state`,
`Engine.Make_Domain.Store.callstacks`,
`Engine.Make_Domain.Store.get_state_by_callstack`, `Engine.Make.get_state`,
`Engine.Make.get_state_by_callstack`, `Engine.Make.callstacks`,
`Reach_delivery.reached`, `Reach_delivery.callstacks`,
`Reach_delivery.Points`, `Reach_delivery.deliver`,
`Reach_delivery.records`, `Reach_delivery.restore`,
`Cvalue_domain.State.Store.is_computed`, `Engine.Make.find`,
`Domain_store.callstacks`, `Eva_results.get_results`,
`Eva_results.set_results`, `Results`.

**Argument (source inspection).** The queries of `Results` read the states
through `Engine.get_state`, `Engine.get_state_by_callstack` and
`Engine.callstacks`, which read the store of `Engine.Make_Domain`. There,
`get_state` answers top at a point and callstack in `Points`, and at a point
without callstack when `Points` holds the point; `callstacks` adds the
callstacks of the hits to those of the analysed calls; and
`get_state_by_callstack` reads both. A hit saves no state: its states are
not known, and top covers every state the analysis of the body would save
there. `Points` is a `State_builder.Hashtbl` that depends on `Self.state`,
so it is cleared with the results of Eva, saved with the session and copied
with the project.

The queries answer `Top` at the points of a function analysed without
saving its states (`Engine.Make.find`, for the status `Analyzed NoResults`),
and the store of the cvalue domain answers `Top` at every point when it
saves no state (`-eva-no-results`, `-eva-no-results-domain cvalue`;
`Domain_store.callstacks`). `Engine.Make_Domain.Store.callstacks` adds the
callstacks of the hits to the callstacks of the analysed calls only, not to
`Top`, and `Results.callstacks` gives the empty list. `Reach_delivery.deliver` records the function as of
unknown reachability when its states are saved and the store of the cvalue
domain, the only domain at a hit, saves none
(`Cvalue_domain.State.Store.is_computed`).

`Eva_results.get_results` copies the states of the store, which do not
hold the points of the hits, and `set_results` clears every state that
depends on `Self.state`, `Points`, `Unknown` and the functions with skipped
visits among them, before it installs the states. The results hold the
records of the hits (`Reach_delivery.records`), and `set_results` installs
them after the clearing (`Reach_delivery.restore`). The results hold
neither the guard outcomes, nor the zones, nor the statuses of
reachability, nor the statistics: `set_results` leaves them empty, with or
without a hit.

**Evidence (executed).** In `cache-reach.t`, the value of `x` before the
statement at line 18 is `{2}` in the callstack of line 29, top in the
callstack of line 30 and over all callstacks; with caching disabled, it is
`{1}` in the callstack of line 30 and `{1; 2}` over all callstacks. In
`loop.c`, where the analysed call and the hit share a callstack, the value
of `x` at line 13 is top in that callstack. The lines of the replay are read
again after `-load` of the session saved after the analysis. Each check
fails with one change, reverted after the run:

- without the answer top in a callstack of a hit: the callstack of line 30
  is missing from all statements, and the statement at line 9 is marked
  unreachable; in `cache-safety.t`, the refinement gives the division alarm
  of `passes.c` the final status valid, and invalid in the reverse order,
  and Export asserts `\false` at line 10 and `x == 2`;
- without the callstacks of the hits: the callstack of line 30 is missing
  from all statements, and the statements of lines 9 and 10 are classified
  as unreachable; the refinement gives the same statuses as above, and
  Export asserts `\false` at line 10;
- without the answer top over all callstacks: the value of `x` over all
  callstacks is `{2}`, and the statement at line 9 is marked unreachable;
- with the state saved by the analysed call answered before the points of
  the hits: the value of `x` at line 13 of `loop.c` is `{2}` in the shared
  callstack, where the hit runs with x = 1.

The results taken and installed again, in `reach.c`: after
`get_results` and `set_results` in the same project, the callstacks of the
statements of `body`, the dead code, the values of `x`, the annotations
that Export generates and the record that the hit skipped the visits of
`body` are those before the installation. The guard outcomes, the zones
and the reachability status of line 15 are lost, with or without the hit.
The lines of the readers after the installation (prefixed `restored | `)
equal those of the installation with caching disabled; the other lines are
not compared with caching disabled, and differ from it as before the
installation: the value of `x` at line 18 is top in the callstack of the
hit and over all callstacks, the visits of `body` are recorded as skipped,
and Export generates `\false` at line 15 only, where caching disabled also
generates `1 ≤ x ≤ 2` at lines 8, 14 and 18 and `l ≡ 1` at line 18. Taken
and installed in a copy of the project (`Project.create_by_copy`), the
results give the same lines, and the original project is unchanged. In
`passes.c`, the refinement of the statuses of alarms run after the
installation leaves the division alarm of line 13 unknown, as with caching
disabled. The entry without a Reach part is rejected, and after the
installation the lines, the values, the annotations of Export and the
response of `getDeadCode` on the session saved after it equal those of
caching disabled. Under `-eva-no-results-domain cvalue`, `body` is of
unknown reachability after the installation, and on the session saved
after it the response of `getDeadCode` is the one without the
installation, with no statement of `body`.

Under `-eva-no-results-domain cvalue`: with caching disabled, the queries
answer no callstack in `body`, `getDeadCode` lists every statement of
`body` as unreachable, and Export generates `\false` before the statements
of lines 14 and 18, although `body` is called. After the hit, `body` is of
unknown reachability: `getDeadCode` lists no statement of `body`, and
Export generates no annotation in it. The guard outcomes, the zones and the
call sites equal those of caching disabled.

Each of these checks fails with one change, reverted after the run:

- `set_results` without the installation of the records, or the records
  without the points: after the installation, the callstack of line 30 is
  missing from the statements of `body`, the statements of lines 9 and 10
  are classified unreachable, the value of `x` at line 18 is `{2}`, and
  Export generates `x ≡ 2` at lines 8, 14 and 18 and `\false` at line 9;
- the records without the functions of unknown reachability
  (`Reach_delivery.restore`): under `-eva-no-results-domain cvalue`, after
  the installation, `body` is not of unknown reachability, and
  `getDeadCode` on the saved session lists every statement of `body` as
  unreachable;
- the record of unknown reachability removed from the delivery under
  `-eva-no-results-domain cvalue`: `getDeadCode` lists every statement of
  `body` as unreachable, and Export generates `\false` before the
  statements of lines 14 and 18, as with caching disabled;
- the records without the functions whose visits a hit skipped: after the
  installation, the visits of `body` are not recorded as skipped. This
  record serves the statistics of a function (`Summary.FunctionStats`),
  which the results do not hold, and the test of complete results
  (`Results.statement_results_complete`), through which From, Inout, Pdg
  and Studia refuse their results computed from statement states
  ([Results computed from statement states are refused after a hit](cache-parts.md#results-computed-from-statement-states-are-refused-after-a-hit)).
  The results hold this record once.

**Open.**

- The values at the statements of a body reached by a hit are top: a reader
  that concludes from them, such as the refinement of the statuses of
  alarms, draws no conclusion there (see
  [The passes after the analysis read the points reached by hits](#the-passes-after-the-analysis-read-the-points-reached-by-hits)),
  and a reader that reports them loses precision
  ([issue #49](https://github.com/nyandrianinamamy/frama-c/issues/49)).
- A callstack that is analysed and answered by a hit at the same call site,
  in two iterations of a loop for instance, answers top at the points the
  hit reaches (`loop.c`), also for an Inner reference that names that
  callstack: the states of the analysed call there are not seen by the
  queries.
- The results taken by `Eva_results.get_results` hold neither the guard
  outcomes, nor the zones, nor the statuses of reachability, nor the
  statistics: after `set_results`, no outcome of a condition is recorded,
  with or without a hit.
- The results taken in a project cannot be installed in another project:
  `set_results` stops with `Two kf for body`, with caching disabled as
  well. This is not tested.
- Under `-eva-no-results-domain cvalue`, the analysis with caching disabled
  reports every statement of a called function unreachable
  (`getDeadCode`, Export), as the queries answer no callstack. The same
  holds at revision 71986dadcb, before the cache. A hit does not repeat this
  conclusion, and draws none in its function either.

## The passes after the analysis read the points reached by hits

**Claim.** After an analysis in which the store of the cvalue domain saves
states, a statement of a function whose states are saved is reported
unreachable only if no analysed call saved a state there and no hit
reached it: the marking of dead code (`Eval_annots.mark_unreachable`), the
coverage of the summary and the server request `getDeadCode` read which
statements are reached through the queries above. The refinement of the
statuses of alarms (`Eval_annots.mark_green_and_red`) and `Export` read the
states, top in the callstacks of the hits, and conclude nothing at a
statement that a hit reaches from the states of the analysed calls alone.
Every hit delivers a Reach part, with its points where the states of the
function are saved: the lookup rejects an entry without a Reach part, and
an entry produced while the states of the body were not saved where they
are saved (`missing-points`). When the store of the cvalue domain saves no
state, the queries see no point, of a hit or of an analysed call: Export
and `getDeadCode` draw no conclusion in the function of a hit
([The passes after the analysis draw no conclusion where the queries do not see the points of a hit](safety.md#the-passes-after-the-analysis-draw-no-conclusion-where-the-queries-do-not-see-the-points-of-a-hit)),
and the other passes conclude nothing, with or without a hit.

**Kind.** OCaml obligation.

**Depends on.**
[The queries see the points reached by a hit, with the state top](#the-queries-see-the-points-reached-by-a-hit-with-the-state-top)
and
[The passes after the analysis draw no conclusion where the queries do not see the points of a hit](safety.md#the-passes-after-the-analysis-draw-no-conclusion-where-the-queries-do-not-see-the-points-of-a-hit).

**Symbols.** `Eval_annots.mark_unreachable`,
`Eval_annots.mark_green_and_red`, `Eval_annots.eval_by_callstack`,
`Export.generator`, `Export.main`, `Summary.compute_fun_stats`,
`Summary.print_coverage`, `Results.is_reachable`, `dead_code` in
[`ast_requests.ml`](../../../plugins/eva/src/server_api/ast_requests.ml),
`Reach_delivery.reach_unknown_of`, `Supplied_entries.Lookup.admit`,
`Compute_functions.Make.compute_and_cache_call`.

**Argument (source inspection).** `mark_unreachable`, the coverage of the
summary (`Summary.compute_fun_stats`) and `dead_code` read
`Results.is_reachable` or the emptiness of the states before and after a
statement, which see the points reached by hits.
`mark_green_and_red` evaluates an alarm on the state of each callstack
before its statement, and emits valid or invalid only when every callstack
agrees; in a callstack of a hit, the state is top, and the evaluation of
the alarm there holds or fails in every state. `Export.generator` builds
its assertions from the state over all callstacks, top at a point that a
hit reaches, and asserts `\false` at a statement without a state.
`Export.generator`, `Export.main` and `dead_code` skip a function of
unknown reachability (`reach_unknown_of`), in place of every function
answered by a hit before issue #48. A function is of unknown reachability
only after a hit under `-eva-no-results-domain cvalue`, where, with
the cvalue domain alone, the store answers `Top` at every point of a
function that the analysis calls: `Results.is_reachable` holds at each of
its statements and the cvalue state at its start is the top state, so that
`mark_unreachable` marks none of them, `mark_green_and_red` emits no status
(`eval_by_callstack` gets no state by callstack and answers `Unknown`) and
the summary counts each as reached, with or without a hit. These three
passes have no gate. A statement that no analysed call and no hit reaches
is a statement that the analysis of the body at each hit would not reach
either, by the claims above.

**Evidence (executed).** In `cache-reach.t`, `reach.c`, the statements of
the branch of `x == 3` are the only ones unreachable, as with caching
disabled; the statement at line 15 gets the reachability status invalid,
and its assertion `three` is valid. The summary of the analysis counts 12
statements reached of 14, as with caching disabled. In `cache-safety.t`,
`passes.c`, the statuses after the hit at line 35 are those of caching
disabled: the division alarm at line 13, valid in the analysed call alone,
is unknown, and `one`, reached through the hit only, is valid with no
reachability status. The summary counts 14 statements reached of 15, as
with caching disabled.
Export asserts `\false` at line 14, which no call reaches, and nothing at
the statements that the hit reaches; with caching disabled, it asserts the
same `\false`, and the values at the other statements. Without the answer
top in the callstacks of the hits, or without these callstacks
([The queries see the points reached by a hit, with the state top](#the-queries-see-the-points-reached-by-a-hit-with-the-state-top)),
the refinement gives the alarm the final status valid, and invalid in the
reverse order, and Export asserts `\false` at line 10, reached by the hit.
When the entry is supplied without its Reach part, or produced with
`-eva-no-results-function body`, the lookup rejects it (`missing-points`),
`body` is analysed, and the lines equal those of caching disabled; after
the rejection of the entry without a Reach part, the summary counts 12
statements reached of 14, as with caching disabled. Under
`-eva-no-results-domain cvalue`, the summary counts 14 statements reached
of 14 with and without the hit. Each check fails with one change, reverted
after the run, in that run: with the test of `reach_unknown_of` removed
from `Export.generator`, Export generates `\false` before the statements
of lines 14 and 18 after the hit; removed from `dead_code`, `getDeadCode`
lists every statement of `body` as unreachable.

The request `getDeadCode` is executed in a second process that loads the
server plug-in, Eva and its server API with a session saved after the
analysis (`test_dead_code.ml`): after the hit, the response for `body`
equals the one after the analysis with caching disabled, with the
statements of lines 15 and 16 unreachable; after the rejection of the
entry without a Reach part and the installation of the results, it equals
the response with caching disabled and the same installation; after the hit
under `-eva-no-results-domain cvalue`, it lists no statement of `body`,
also after the results are taken and installed again. With the
queries blind to the points of hits (`Reach_delivery.reached` false, a
mutation reverted after the run), the response after the hit lists the
statements of lines 9 and 10 as unreachable. The analysis of this test
does not load the server. With the server loaded and not started, its
client of the hooks on the changes of annotations is audited at the lookup
([A hit runs no client that is not audited](safety.md#a-hit-runs-no-client-that-is-not-audited)),
and the hits occur in the process of the request: in `cache-parts.t`,
`getDeadCode` after the hits on `copy` and `narrow`, in that process and
on the saved session, gives the reached statements of caching disabled
([Results computed from statement states are refused after a hit](cache-parts.md#results-computed-from-statement-states-are-refused-after-a-hit)).

**Open.**

- The plug-ins rejected as `consumer`, among them Nonterm, Metrics and the
  Markdown report, which read whether a statement is reached, stay
  rejected; their use of the points reached by hits is not checked.
- The refinement and Export gain nothing at the statements that a hit
  reaches, where caching disabled may conclude from precise states
  ([issue #49](https://github.com/nyandrianinamamy/frama-c/issues/49)).
