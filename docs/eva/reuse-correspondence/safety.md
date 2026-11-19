# Safety at a hit

Claims about the Safety part of a cache entry, added by
[issue #47](https://github.com/nyandrianinamamy/frama-c/issues/47): the
alarms, statuses and red contexts that the analysis of a body emits are
recorded with its entry, and a hit delivers them. In this version, only
entries supplied by a test module reach a hit (see
[Reuse operation](reuse-operation.md)).

The modules are
[`safety_part.ml`](../../../plugins/eva/src/engine/safety_part.ml) (the
writes and their recording),
[`safety_delivery.ml`](../../../plugins/eva/src/engine/safety_delivery.ml)
(their delivery at a hit) and the hit branch of
`Compute_functions.Make.compute_and_cache_call` in
[`compute_functions.ml`](../../../plugins/eva/src/engine/compute_functions.ml).
The fixture is
[`cache-safety.t`](../../../plugins/eva/tests/utils/cache-safety.t/run.t). It
takes one entry from a first analysis of the body in the same process, after
which a change of the entry point resets the alarms and statuses of Eva, and
writes another entry by hand. It compares each run with the same program
analysed with caching disabled, and gives the expected values by hand.

## The Safety part records the writes of the body

**Claim.** While a body is analysed after a lookup without a hit, each alarm
that Eva registers, each status that it emits on a property with its own
emitter and each red context that it adds is recorded once, in the order of
its first emission, with its statement or property, its status, its emitter
and the calls between the body and the point of emission (its frames). The
checks of the `requires` clauses of the called function belong to the call
site and are not recorded. The producer stores these writes in the entry as
its Safety part.

**Kind.** OCaml obligation.

**Depends on.**
[Side tables and recorded joins](body-access.md#side-tables-and-recorded-joins)
and
[Provenance, storage and lookup](cache-producer.md#provenance-storage-and-lookup).

**Symbols.** `Safety_part.capture`, `Safety_part.record_alarm`,
`Safety_part.emit_status`, `Safety_part.record_red_context`,
`Alarmset.emit_alarm`, `Alarmset.register`, `Transfer_logic.emit_status`,
`Red_statuses.add_red_ap`, `Body_access.at_call_site`,
`Cache_producer.produce`, `Cache_entry.Make.safety`.

**Argument (source inspection).** `compute_and_cache_call` runs
`Body_access.capture` inside `Safety_part.capture`, with the callstack of the
call, in the branch `No_candidate` only, and passes the writes to
`Call_cache.Make.store`, which gives them to the producer. A write is
recorded when a capture is active and the collector observes the body
(`Body_access.is_recording`). `Transfer_logic.check_fct_preconditions
~body:true` checks the `requires` clauses under `Body_access.at_call_site`,
which suspends that observation, as does `Body_access.without_recording`.
The frames of a write are the calls of the current callstack above the
callstack of the capture. A write whose callstack does not extend it
refuses the body as `side-table`. A write equal to one already recorded is
not added again: the tables below join a value with itself into the same
value.

During an analysis, Eva writes alarms, statuses and red contexts through
three functions, each of which records the write:

- `Alarmset.register`, reached from `Alarmset.emit_alarm` for each alarm of
  an evaluation, calls `Alarms.register` with the status;
- `Transfer_logic.emit_status`, for the statuses of code annotations and of
  the clauses of the contract of the analysed function, calls
  `Property_status.emit ~distinct:true` through `Safety_part.emit_status`;
- `Red_statuses.add_red_ap` adds a red context.

The other writers of statuses in Eva do not run in a body that the producer
stores. `Recursion.mark_unknown_requires` runs at a call made by the body,
and `Transfer_stmt` refuses such a body as `nested-call`.
`Logic_inout.check_fct_assigns` runs in the callwise hooks of From and Inout,
outside the observation; a supplied entry is rejected as `consumer` when
either plug-in is loaded
([A supplied entry is used with cvalue alone and no consumer of memexec identifiers](reuse-operation.md#a-supplied-entry-is-used-with-cvalue-alone-and-no-consumer-of-memexec-identifiers)).
`Eval_annots` runs after the analysis, and `Eva_results` and `Export` do not
run during one. Since a body with a call refuses, and the producer refuses a
callee with `requires` clauses (`preconditions`), every write of a produced
entry has empty frames.

**Evidence (executed).** In `cache-safety.t`, the entry of `body` produced by
the analysis from `producer`, at x = 1 and y = 0, has five writes, all with
empty frames: the red context and the invalid status of the assertion `two`,
the red context of the division alarm, the alarm with an unknown status, and
the valid status of `ok`. With caching disabled, the Safety part observed for
each call of `pre` is empty, although the evaluation of its `requires` clause
emits an invalid status at the second call.

**Open.**

- The iterator still consults the history of the alarms emitted
  (`Alarmset.already_emitted`) and refuses as `side-table`
  ([Side tables and recorded joins](body-access.md#side-tables-and-recorded-joins)).
  A body analysed after one of its own alarms was emitted gives no entry; the
  reference run of `cache-safety.t` shows it for the second call of `body`.
- A produced entry has no write with frames. The fixture delivers writes
  with a frame added by hand only. The composition with nested calls is
  [issue #50](https://github.com/nyandrianinamamy/frama-c/issues/50) and
  [issue #51](https://github.com/nyandrianinamamy/frama-c/issues/51).
- That the three functions above are the only writers reached from a stored
  body is shown by source inspection only.

## A hit delivers the Safety part as recorded joins

**Claim.** At a hit on a supplied entry, when a state satisfies the
preconditions of the called function (see
[Preconditions at a hit](#preconditions-at-a-hit)), the writes of the Safety
part are made again, in their order, each for the callstack of the hit
extended by its frames. Each write goes through the function that the body
uses, so that the kernel or Eva joins it with the value already at its
position. This is an instance of the `RecordedWrite` contract of
[Side-table obligations for skipped work](hit.md#side-table-obligations-for-skipped-work)
for the four tables below, under the premise that the saved writes are those
that an analysis of the body at the hit would make.

**Kind.** OCaml obligation. The instance of the Lean predicate
`ReuseModel.SideTables.RecordedWrite` is argued in prose; no Lean statement
is instantiated for Eva.

**Depends on.**
[The Safety part records the writes of the body](#the-safety-part-records-the-writes-of-the-body),
[Hit soundness](hit.md#hit-soundness),
[Side-table obligations for skipped work](hit.md#side-table-obligations-for-skipped-work)
and [The match by equality](reuse-operation.md#the-match-by-equality).

**Symbols.** `Safety_delivery.deliver`, `Alarmset.deliver`,
`Alarmset.register`, `Safety_part.emit_status`,
`Red_statuses.add_red_context`, `Alarms.register`, `Property_status.emit`
and `merge_distinct_emitted` in
[`property_status.ml`](../../../src/kernel/services/ast_data/property_status.ml),
`Supplied_entries.Lookup.find`, `Call_cache.Make.lookup`,
`Compute_functions.Make.compute_and_cache_call`.

**Argument (source inspection).** The parameters of `RecordedWrite` for each
table:

| Table | Position | Value | Observations represented | Join |
| --- | --- | --- | --- | --- |
| statuses of Eva (`Property_status`) | property, emitter | none, valid, invalid or unknown | the visits of the property, with the outcomes the status allows: holds for valid, fails for invalid, both for unknown | none is the unit; valid and invalid give unknown; unknown absorbs both |
| alarms of Eva (`Alarms`) | statement, alarm, emitter | absent, or present with a status | the visits of the statement at which the undefined behaviour may occur, with the outcomes its status allows | presence by or; status as in the first row |
| alarms reported by the analysis (`Alarmset.Alarm_cache`) | statement, alarm | reported or not | the report of the alarm | or |
| red contexts (`Red_statuses`) | statement, alarm or property | set of callstacks | the callstacks in which every visit of the statement violates the property | union |

*Laws.* During an analysis, Eva emits valid, invalid (`False_if_reachable`)
and unknown (`Dont_know`). With "none" below them, these form a join
semilattice in which valid and invalid are below unknown, so the join is
associative, commutative and idempotent. Unknown allows both outcomes, so the
join covers both operands. `False_and_reachable`, above unknown, is emitted
by `Eval_annots` after the analysis only. Or and union are associative,
commutative and idempotent, and cover both operands.

*Replay at the position.* `Property_status.emit ~distinct:true` computes the
new status of the emitter from its previous status with
`merge_distinct_emitted`, `Unmergeable` giving `Dont_know`: this is the join
above, so the value after the write is the join of the value before and the
saved status. `Alarms.register` creates the alarm once and emits its status
in the same way. `Alarm_cache.memo` adds the alarm and reports it if it is
absent, as for a fresh emission. `Red_statuses.add_red_ap` adds the current
callstack to the set. The tables of statuses and alarms have no callstack
in their positions: a write has the same position at every hit, and a second
delivery leaves the value unchanged by idempotence. The red contexts are
indexed by callstack: `deliver` makes the callstack of the hit, extended by
the frames of the write, the current one, so that each hit adds its own.

*Fresh contribution.* The match by equality gives a hit only when the input
of the call equals the stored input on the key. Exit reuse of a produced
entry rests on the premise that the analysis of the body depends on its
input through the key only
([Producer obligations for exit reuse](cache-producer.md#producer-obligations-for-exit-reuse)).
Under the same premise, the writes that an analysis of the body at the hit
would make are the saved writes, at the callstack of the hit. The value
after the delivery is the join of the value before with these writes, which
covers both. For a hand-written entry, the supplier owes the Safety part
(`Supplied_entries.supply`). The [hit theorem](hit.md#hit-soundness) states
the coverage of Safety for concrete executions under its own premises;
whether Eva's statuses meet them is the open premise of the Exit claim as
well.

*Other positions.* `deliver` writes at the positions of the saved writes
only. The hooks that a write triggers, the updates of the kernel on a new
status and the hook of `Red_statuses`, are those of a fresh emission.

*Repeated and nested work.* A body that emits the same write at several
visits records it once, which the idempotence of the joins makes equivalent.
A hit inside a body under analysis records its delivered writes in that body
through the same functions, with the frames of the hit, but a body with a
call refuses as `nested-call`.

**Evidence (executed).** `cache-safety.t`, in one process: a first analysis
from `producer` stores the entry of `body(1, 0)`. Changing the entry point
to `main` resets the analysis, after which no status and no red context is
left. The entry is supplied to a second analysis from `main`. The call
`body(2, v & 1)` has another key and is analysed; by hand, `two` is valid
there and the division alarm unknown. The call `body(1, 0)` at line 26 reads
`lookup: hit (entry 1); execution: not-analysed`. After the analysis, `two`
is unknown, the join of valid and invalid; the alarm is unknown; `ok` is
valid; `two` and the alarm each have one red context, in
`body :: safety.c:26 <- main`; and r1 = 9, r2 = 8 at the end of `main`. The
same program analysed with caching disabled gives the same lines. With the
delivery removed from the hit branch, the test fails: `two` is valid and
neither red context is present.

The alarm is also emitted by the analysed call, so the comparison above
does not see its delivery. The fixture therefore delivers the Safety part
outside any analysis, after the same reset, for the callstack of the call
at line 26: the alarm is registered with its warning, its unknown status and
its red context, and `two` is invalid. A second delivery at that callstack
changes no status and no red context, and prints no warning. The red
contexts, delivered again with the call of `body` in `outer` as frame for a
callstack that starts in `outer`, get the context
`body :: safety.c:44 <- outer`. With the delivery of alarms removed, this
part of the test fails: the alarm, its status and its warning are missing.

**Open.**

- The statuses that the passes after the analysis emit can differ from
  those of caching disabled: see
  [Statuses after the analysis with an entry from another analysis](#statuses-after-the-analysis-with-an-entry-from-another-analysis).
- The messages that accompany a status (`Transfer_logic.msg_status`) are not
  recorded and a hit does not print them. They are printed with `~once:true`:
  the logger prints a message only if it has not printed the same text at
  the same position before. Within one analysis, the call that produced the
  entry printed the same message, so a replay would print nothing more. With
  the message category `callstacks` of Eva, the text includes the callstack
  and the message of the hit's callstack is missing.
- `Alarmset.deliver` applies `-eva-stop-at-nth-alarm` after each delivered
  alarm, as after the alarms of an evaluation; no fixture exercises it.
- The entries are not saved with a session: the tables of supplied and
  produced entries are not marshalled. Cache state in a saved session is
  [issue #59](https://github.com/nyandrianinamamy/frama-c/issues/59).
- An entry taken from another analysis is a fixture device. The reset of
  Eva removes its alarms, and the delivery creates them again as a fresh
  emission would; the statuses of the annotations of the program are those
  of the second analysis only.

## Statuses after the analysis with an entry from another analysis

**Kind.** Known difference.

**Claim.** `Eval_annots.mark_green_and_red` and
`Eval_annots.mark_unreachable` run after the analysis on the states saved
for each callstack, and a hit saves none for its own. With an entry taken
from another analysis, the first evaluates an alarm again on the states of
the analysed calls only, and can give it a final status that the hit
contradicts; the second marks dead a statement reached through hits only,
which overwrites its statuses. The statuses then differ from those of
caching disabled.

**Model coverage.** The hit theorem covers the statuses delivered at the
hit. The passes after the analysis are not in the model.

**Evidence (executed for the refinement, source inspection for dead-code
marking).** In `cache-safety.t`, from `main2`, the analysed call
`body(2, 1)` never divides by zero, and the call `body(1, 0)` at line 37 is
a hit on the entry from the analysis from `producer`. The refinement gives
the division alarm the final status valid, although the hit makes it a sure
alarm; with caching disabled, the alarm is unknown. The main fixture avoids
both passes: each statement with a delivered write is reached by the
analysed call, where the alarm is unknown.

**To extend coverage.** Reached statements at a hit are
[issue #48](https://github.com/nyandrianinamamy/frama-c/issues/48). The
refinement of unknown statuses per key group, with its outcome recorded in
the Safety part, is
[issue #49](https://github.com/nyandrianinamamy/frama-c/issues/49).

## Preconditions at a hit

**Claim.** At a hit, the preconditions of the called function are evaluated
for the call, outside the entry, and their statuses are emitted at the call.
When no state satisfies them, a hit on a supplied entry delivers neither its
Safety part nor its exit states, and the call has no state at its end, as
when the body is analysed. A memexec hit keeps its states, as before.

**Kind.** OCaml obligation.

**Depends on.**
[A hit delivers the Safety part as recorded joins](#a-hit-delivers-the-safety-part-as-recorded-joins).

**Symbols.** `Compute_functions.Make.compute_and_cache_call`,
`Transfer_logic.Make.check_fct_preconditions`, `Iterator`,
`Cache_producer.has_preconditions`, `Supplied_entries.supply`.

**Argument (source inspection).** An analysed body checks its `requires`
clauses first (`Iterator`, `check_fct_preconditions ~body:true`) and
analyses the body from the states that satisfy them: from none, it analyses
nothing and returns no state. The hit evaluates the same clauses on the
input of the call and, when no state is left, returns the empty list without
delivering. When a state is left, the entry's writes and exit states are
those of its stored input, which may include executions that the clauses
exclude. No produced entry is in this case, since the producer refuses a
called function with `requires` clauses (`preconditions`); for a
hand-written entry, the supplier owes it.

**Evidence (executed).** In `cache-safety.t`, a hand-written entry of `pre`
for x = 1 answers the call `pre(1)` at line 15, where g = 0. The
precondition `positive` is reported invalid at line 15, its instance at
that call is invalid and has the red context of the call, and no state
reaches the end of `main`. The same program analysed with caching disabled
gives the same lines. Without the rule, the test fails: the exit state of
the entry is used and `out = 5` holds at the end of `main`.

**Open.** A precondition that narrows the input without emptying it is not
applied to the entry.
