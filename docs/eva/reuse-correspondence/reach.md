# Reach at a hit

Claims about the Reach part of a cache entry, added by
[issue #48](https://github.com/nyandrianinamamy/frama-c/issues/48): the
control points that the analysis of a body reaches, its guard outcomes, the
zones it reads and writes at each statement and the call sites of the calls
it makes are recorded with its entry, and a hit delivers them for its
callstack. In this version, only entries supplied by a test module reach a
hit (see [Reuse operation](reuse-operation.md)).

The modules are
[`reach_part.ml`](../../../plugins/eva/src/engine/reach_part.ml) (the
writes and their recording),
[`reach_delivery.ml`](../../../plugins/eva/src/engine/reach_delivery.ml)
(their delivery at a hit, the points reached by hits and the functions of
unknown reachability), the store of states seen by the queries,
`Engine.Make_Domain.Store` in
[`engine.ml`](../../../plugins/eva/src/engine/engine.ml), and the hit branch
of `Compute_functions.Make.compute_and_cache_call`. The fixture is
[`cache-reach.t`](../../../plugins/eva/tests/utils/cache-reach.t/run.t). As
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
joined. The producer stores these writes in the entry as its Reach part
when the states of the body are saved in the analysis; otherwise the entry
has no Reach part, since the points reached are not recorded. A recording
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
`Function_calls.register_analysis_target`, `Cache_producer.produce`,
`Cache_entry.Make.reach`, `Compute_functions.Make.compute_and_cache_call`.

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
the caller, if any. The producer keeps the part only when `save_results`
holds for the body (`Cache_producer.produce`), since `merge_results` saves
no state otherwise.

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
and the zones of five statements. With `-eva-no-results-function body` in
the analysis from `producer`, the entry has no Reach part. In `enclosing.c`,
the part of `parent` holds the start and the call site of `child`, with the
call of `child` as frame, and none of the writes of `child` when the
analysis of `parent` analyses `child`; when a hit answers that call, it
holds the points, the guard outcome and the zones of `child`, with the call
of `child` as frame. With the recording of the points removed from
`register_state` (a mutation, reverted), the part has no point, and the
comparison of the hit with caching disabled fails.

**Open.**

- The Reach part of a body with a call is incomplete, and no hit delivers
  it ([Composition along the observed path](nested-calls.md#composition-along-the-observed-path)).
- That these four writers are the only ones reached from a stored body is
  shown by source inspection only.

## A hit delivers the Reach part as recorded joins

**Claim.** At a hit on a supplied entry with a Reach part, when a state
satisfies the preconditions of the called function, each write of the Reach
part is made again for the callstack of the hit extended by its frames: the
points are recorded as reached in that callstack when the states of the
called function are saved in the analysis, the guard outcomes and the zones
are joined with those at their positions, and the call sites are added.
This is an instance of the `RecordedWrite` contract of
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
`Function_calls.register_caller`, `Reach_part.reroot`,
`Supplied_entries.reach`, `Compute_functions.Make.compute_and_cache_call`,
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
callstack of the hit, so that each hit adds its own. The points are written
only when `save_results` holds for the called function in the analysis of
the hit, as `merge_results` saves states only then; a write of the points
also records them in the Reach part of an enclosing body under analysis.

*Fresh contribution.* As for the Safety part: the match by equality gives a
hit only when the input of the call equals the stored input on the key, and
under the premise that the analysis of the body depends on its input through
the key only
([Producer obligations for exit reuse](cache-producer.md#producer-obligations-for-exit-reuse)),
the writes that an analysis of the body at the hit would make are the saved
writes, at the callstack of the hit. For a hand-written entry, the supplier
owes the Reach part (`Supplied_entries.supply`).

*Other positions.* `deliver` writes at the positions of the saved writes
only. The four tables are internal to their modules, which register no hook
on them: the delivery runs no hook, and adds none to those of
[A hit runs no client that is not audited](safety.md#a-hit-runs-no-client-that-is-not-audited).

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
caching disabled.

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
- the set of holders of the produced entry left empty: `gp` holds the
  address of `x` at the end of `main` in `holder.c`, and the address of
  `local` in `escape.c`.

**Open.**

- The call sites of calls below the body (non-empty frames) and the start
  of a called function are delivered only by the part of a body with a
  call, which no hit delivers (`nested-delivery`, issue #50): their delivery
  is not executed.
- A hit delivers no analysis status for the functions called below the
  body ([issue #51](https://github.com/nyandrianinamamy/frama-c/issues/51)).

## The queries see the points reached by a hit, with the state top

**Claim.** For a control point reached by a hit in a callstack, the queries
of the results of Eva see that callstack among those of the point, and
answer the state top there; the state over all callstacks is top as well.
The states saved by the analysed calls are not changed. The points reached
by hits are a state of the analysis: reset with its results, and saved and
loaded with a session.

**Kind.** OCaml obligation.

**Depends on.**
[A hit delivers the Reach part as recorded joins](#a-hit-delivers-the-reach-part-as-recorded-joins).

**Symbols.** `Engine.Make_Domain.Store.get_state`,
`Engine.Make_Domain.Store.callstacks`,
`Engine.Make_Domain.Store.get_state_by_callstack`, `Engine.Make.get_state`,
`Engine.Make.get_state_by_callstack`, `Engine.Make.callstacks`,
`Reach_delivery.reached`, `Reach_delivery.callstacks`,
`Reach_delivery.Points`, `Results`.

**Argument (source inspection).** The queries of `Results` read the states
through `Engine.get_state`, `Engine.get_state_by_callstack` and
`Engine.callstacks`, which read the store of `Engine.Make_Domain`. There,
`get_state` answers top at a point and callstack in `Points`, and at a point
without callstack when `Points` holds the point; `callstacks` adds the
callstacks of the hits to those of the analysed calls; and
`get_state_by_callstack` reads both. A hit saves no state: its states are
not known, and top covers every state the analysis of the body would save
there. `Points` is a `State_builder.Hashtbl` that depends on `Self.state`,
so it is cleared with the results of Eva and saved with the session.

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
- `Eva_results.get_results` and `Eva_results.set_results` read and write
  the states of the store: they do not carry the points reached by hits,
  nor the functions of unknown reachability and those whose visits a hit
  skipped.

## The passes after the analysis read the points reached by hits

**Claim.** After an analysis, a statement of a function is reported
unreachable only if no analysed call saved a state there and no hit
reached it: the marking of dead code (`Eval_annots.mark_unreachable`), the
coverage of the summary and the server request `getDeadCode` read which
statements are reached through the queries above. The refinement of the
statuses of alarms (`Eval_annots.mark_green_and_red`) and `Export` read the
states, top in the callstacks of the hits, and conclude nothing at a
statement that a hit reaches from the states of the analysed calls alone.
A hit on an entry without a Reach part, an entry written by hand without
one or produced while the states of the body were not saved, reaches no
point: these passes draw no conclusion in its function
([The passes after the analysis draw no conclusion where a hit reached no point](safety.md#the-passes-after-the-analysis-draw-no-conclusion-where-a-hit-reached-no-point)).

**Kind.** OCaml obligation.

**Depends on.**
[The queries see the points reached by a hit, with the state top](#the-queries-see-the-points-reached-by-a-hit-with-the-state-top)
and
[The passes after the analysis draw no conclusion where a hit reached no point](safety.md#the-passes-after-the-analysis-draw-no-conclusion-where-a-hit-reached-no-point).

**Symbols.** `Eval_annots.unreached`, `Eval_annots.mark_unreachable`,
`Eval_annots.mark_green_and_red`, `Export.generator`, `Export.main`,
`Summary.reached`, `Summary.unknown_reachability`,
`Summary.print_coverage`, `dead_code` in
[`ast_requests.ml`](../../../plugins/eva/src/server_api/ast_requests.ml),
`Reach_delivery.reach_unknown`, `Reach_delivery.reach_unknown_of`,
`Reach_delivery.reach_unknown_at`,
`Compute_functions.Make.compute_and_cache_call`.

**Argument (source inspection).** `Eval_annots.unreached`, `Summary.reached`
and `dead_code` read `Results.is_reachable` or the emptiness of the states
before and after a statement, which see the points reached by hits.
`mark_green_and_red` evaluates an alarm on the state of each callstack
before its statement, and emits valid or invalid only when every callstack
agrees; in a callstack of a hit, the state is top, and the evaluation of
the alarm there holds or fails in every state. `Export.generator` builds
its assertions from the state over all callstacks, top at a point that a
hit reaches, and asserts `\false` at a statement without a state. These
passes and `Export.main` skip a function of unknown reachability
(`reach_unknown_of`, `reach_unknown_at`), in place of every function
answered by a hit before issue #48. A statement that no analysed call and
no hit reaches is a statement that the analysis of the body at each hit
would not reach either, by the claims above.

**Evidence (executed).** In `cache-reach.t`, `reach.c`, the statements of
the branch of `x == 3` are the only ones unreachable, as with caching
disabled; the statement at line 15 gets the reachability status invalid,
and its assertion `three` is valid. The summary of the analysis counts 12
statements reached of 14, as with caching disabled. In `cache-safety.t`,
`passes.c`, the statuses after the hit at line 35 are those of caching
disabled: the division alarm at line 13, valid in the analysed call alone,
is unknown, and `one`, reached through the hit only, is valid with no
reachability status. The summary counts 14 statements reached of 15, as
with caching disabled, where it counted 12, and up to 3 more, before.
Export asserts `\false` at line 14, which no call reaches, and nothing at
the statements that the hit reaches; with caching disabled, it asserts the
same `\false`, and the values at the other statements. Without the answer
top in the callstacks of the hits, or without these callstacks
([The queries see the points reached by a hit, with the state top](#the-queries-see-the-points-reached-by-a-hit-with-the-state-top)),
the refinement gives the alarm the final status valid, and invalid in the
reverse order, and Export asserts `\false` at line 10, reached by the hit.
When the entry is supplied without
its Reach part, or produced with `-eva-no-results-function body`, `body` is
of unknown reachability: no statement of `body` gets a reachability
status, and the summary counts 10 statements reached of 14, and up to 4
more. Each check fails with one change, reverted after the run: without
the record of unknown reachability, the statement at line 9, reached by the
hit, is marked unreachable when the entry has no Reach part, and the
summary prints no range; with the Reach part kept by the producer when the
states are not saved, the same statement is marked unreachable after the
hit on the entry produced with `-eva-no-results-function body`.

The request `getDeadCode` rests on source inspection: the fixture prints
the classification it computes from the same queries. A hit does not meet
it in this version: the server plug-in registers a client of the hooks on
the changes of annotations when it loads, and every supplied entry is
then rejected
([A hit runs no client that is not audited](safety.md#a-hit-runs-no-client-that-is-not-audited)).

**Open.**

- The plug-ins rejected as `consumer`, among them Nonterm, Metrics and the
  Markdown report, which read whether a statement is reached, stay
  rejected; their use of the points reached by hits is not checked.
- The refinement and Export gain nothing at the statements that a hit
  reaches, where caching disabled may conclude from precise states
  ([issue #49](https://github.com/nyandrianinamamy/frama-c/issues/49)).
