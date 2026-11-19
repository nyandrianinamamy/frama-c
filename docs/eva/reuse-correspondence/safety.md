# Safety at a hit

Claims about the Safety part of a cache entry, added by
[issue #47](https://github.com/nyandrianinamamy/frama-c/issues/47): the
alarms, statuses, messages of statuses and red contexts that the analysis of
a body emits are recorded with its entry, and a hit delivers them. In this
version, only entries supplied by a test module reach a hit (see
[Reuse operation](reuse-operation.md)).

The modules are
[`safety_part.ml`](../../../plugins/eva/src/engine/safety_part.ml) (the
writes and their recording),
[`safety_delivery.ml`](../../../plugins/eva/src/engine/safety_delivery.ml)
(their delivery at a hit, and the functions whose visits a hit skips) and
the hit branch of `Compute_functions.Make.compute_and_cache_call` in
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
emitter, the message printed with the status of a code annotation or of a
postcondition, and each red context that it adds are recorded in one
sequence, in the order of emission. An alarm, a status or a message is
recorded at its first emission only. A red context is recorded at each
emission, in its place among the other writes; red contexts set in a row,
with no other write recorded between them, form one write that keeps their
number. Each write keeps its statement or property, its status, its emitter
or its text, and the calls between the body and the point of emission (its
frames). The checks of the `requires` clauses of the called function
belong to the call site and are not recorded. The producer stores these
writes in the entry as its Safety part. A recording belongs to the project
that is current when it starts (see
[A change of the current project refuses the recordings in progress](#a-change-of-the-current-project-refuses-the-recordings-in-progress)).

**Kind.** OCaml obligation.

**Depends on.**
[Side tables and recorded joins](body-access.md#side-tables-and-recorded-joins)
and
[Provenance, storage and lookup](cache-producer.md#provenance-storage-and-lookup).

**Symbols.** `Safety_part.capture`, `Safety_part.record_alarm`,
`Safety_part.emit_status`, `Safety_part.status_message`,
`Safety_part.record_red_context`, `Alarmset.emit_alarm`,
`Alarmset.register`, `Transfer_logic.emit_status`,
`Transfer_logic.body_msg_status`, `Red_statuses.add_red_context`,
`Body_access.at_call_site`, `Cache_producer.produce`,
`Cache_entry.Make.safety`.

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
refuses the body as `side-table`. An alarm, a status or a message equal to
one already recorded is not added again: the tables below join a value with
itself into the same value, `Property_status.emit ~distinct:true` emits
nothing and runs no hook for a status equal to the previous one
(`merge_distinct_emitted`), and the logger prints nothing and applies no
action for a text printed before with `~once:true`. A red context runs the
hooks of red statuses each time it is set, so it is added at each emission;
when the last write recorded is the same red context, its count is
incremented instead.

During an analysis, Eva writes alarms, statuses, their messages and red
contexts through four functions, each of which records the write:

- `Alarmset.register`, reached from `Alarmset.emit_alarm` for each alarm of
  an evaluation, calls `Alarms.register` with the status;
- `Transfer_logic.emit_status`, for the statuses of code annotations and of
  the clauses of the contract of the analysed function, calls
  `Property_status.emit ~distinct:true` through `Safety_part.emit_status`;
- `Safety_part.status_message`, reached through
  `Transfer_logic.body_msg_status` from `emit_code_annot_status` and from
  `emit_contract_status` for the clauses other than `requires`, prints the
  message of the status; the message of a `requires` clause belongs to the
  call site and is printed by `msg_status`, as before;
- `Red_statuses.add_red_context` adds a red context and runs the hooks of
  red statuses.

The other writers of statuses in Eva do not run in a body that the producer
stores. `Recursion.mark_unknown_requires` runs at a call made by the body,
and `Transfer_stmt` refuses such a body as `nested-call`.
`Logic_inout.check_fct_assigns` runs in the callwise hooks of From and Inout,
outside the observation; a supplied entry is rejected as `consumer` when
either plug-in is loaded
([A supplied entry is used only where a hit is supported](reuse-operation.md#a-supplied-entry-is-used-only-where-a-hit-is-supported)).
`Eval_annots` runs after the analysis, and `Eva_results` and `Export` do not
run during one. Since a body with a call refuses, and the producer refuses a
callee with `requires` clauses (`preconditions`), every write of a produced
entry has empty frames.

**Evidence (executed).** In `cache-safety.t`, the entry of `body` produced by
the analysis from `producer`, at x = 1 and y = 0, has seven writes, all with
empty frames: the red context, the invalid status and the message of the
assertion `two`, the red context of the division alarm, the alarm with an
unknown status, and the valid status and the message of `ok`. In `loop.c`,
the red context of the check `mixed`, which fails at two iterations of the
loop, is recorded at each failure: the first before the invalid status and
its message, the second after them. In `repeat.c`, the check `never` fails
at the three iterations: after the first, its status and message are those
already recorded, and the next two red contexts form one write with the
count 2. With caching disabled, the Safety
part observed for each call of `pre` is empty, although the evaluation of its
`requires` clause emits an invalid status at the second call.

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
- That the four functions above are the only writers reached from a stored
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
for the five tables below, under the premise that the saved writes are those
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
`Safety_part.status_message`, `Red_statuses.add_red_context`,
`Alarms.register` in
[`alarms.ml`](../../../src/kernel/services/ast_data/alarms.ml),
`Property_status.emit` and `merge_distinct_emitted` in
[`property_status.ml`](../../../src/kernel/services/ast_data/property_status.ml),
`Supplied_entries.Lookup.find`, `Call_cache.Make.lookup`,
`Compute_functions.Make.compute_and_cache_call`.

**Argument (source inspection).** The parameters of `RecordedWrite` for each
table:

| Table | Position | Value | Observations represented | Join |
| --- | --- | --- | --- | --- |
| statuses (`Property_status`) | property, emitter | none, valid, invalid or unknown | the visits of the property, with the outcomes the status allows: holds for valid, fails for invalid, both for unknown | none is the unit; valid and invalid give unknown; unknown absorbs both |
| annotations of alarms (`Alarms`) | statement, alarm | present or absent | the existence of the annotation that states the alarm; its statuses are those of the first row, one per emitter, and its owner is outside the law (see below) | or |
| alarms reported by the analysis (`Alarmset.Alarm_cache`) | statement, alarm | reported or not | the report of the alarm | or |
| messages of statuses (the table of `Log` for messages printed once) | position, text and kind of the message | printed or not | the report of the status, and the action of its message category when it is printed | or |
| red contexts (`Red_statuses`) | statement, alarm or property | set of callstacks | the callstacks in which at least one visit of the statement violates the property | union |

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
saved status. `Alarms.register` creates the annotation of the alarm when it
is absent, with the emitter of the call as owner, and in every case emits the
status of that emitter on the annotation. The existence of the annotation is
thus separate from its statuses, and joins by or. Its owner, the emitter
that registered it first, is not a join: it depends on the order of the
registrations, and is the subject of
[The owner of an alarm is that of an analysis of the body](#the-owner-of-an-alarm-is-that-of-an-analysis-of-the-body).
`Alarm_cache.memo` adds the alarm and reports it if it is absent,
as for a fresh emission. `Safety_part.status_message` prints the text with
`~once:true`, as the body does: the logger prints it only if it has not
printed the same text, of the same kind, at the same position before, and
applies the action of the category `alarm` (abort, error) when it prints it.
`Red_statuses.add_red_context` adds the current callstack to the set and runs
the hooks of red statuses as many times as the count of the write. The
tables of statuses, alarms and messages have no callstack in their
positions, except for a message printed with the category `callstacks`,
whose text holds the callstack: a write has the same position at every hit,
and a second delivery leaves the value unchanged by idempotence. The red
contexts are indexed by callstack: `deliver` makes the callstack of the hit,
extended by the frames of the write, the current one, so that each hit adds
its own.

*Fresh contribution.* The match by equality gives a hit only when the input
of the call equals the stored input on the key. Exit reuse of a produced
entry rests on the premise that the analysis of the body depends on its
input through the key only
([Producer obligations for exit reuse](cache-producer.md#producer-obligations-for-exit-reuse)).
Under the same premise, the writes that an analysis of the body at the hit
would make are the saved writes, at the callstack of the hit. The value
after the delivery is the join of the value before with these writes, which
covers both. For a hand-written entry, the supplier owes the Safety part
(`Supplied_entries.supply`), and for every entry the premise of
[The settings that decide the alarms and messages are those of each hit](#the-settings-that-decide-the-alarms-and-messages-are-those-of-each-hit).
The [hit theorem](hit.md#hit-soundness) states the coverage of Safety for
concrete executions under its own premises; whether Eva's statuses meet them
is the open premise of the Exit claim as well.

*Other positions.* `deliver` writes at the positions of the saved writes
only. The hooks that a write triggers, the updates of the kernel on a new
status and the hooks of `Red_statuses`, are those of a fresh emission. The
writes are delivered in the order of the sequence, so the hooks of red
statuses run once for each time the body set a red context, as
`Red_statuses.register_hook` promises, and in the same order relative to the
messages and to the other writes as in the analysis of the body: an action
of a category that stops the analysis at a message finds the same number of
calls of the hooks before it.

*Repeated and nested work.* A body that emits the same alarm, status or
message at several visits records it once, which the idempotence of the
joins makes equivalent: a later equal write changes no value, runs no hook
of the kernel and prints nothing. Each red context is kept in the sequence,
those set in a row as one write with their number. A hit
inside a body under analysis records its delivered writes in that body
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
`body :: safety.c:33 <- outer`. With the delivery of alarms removed, this
part of the test fails: the alarm, its status and its warning are missing.

Messages, in `message.c`, where the hit at line 25 makes the assertion `two`
invalid. The first analysis runs with the category `alarm` inactive, so
that it prints no message of the category. With the category set to abort,
the analysis with caching disabled stops at `two` in the call at line 25,
and the analysis with the hit stops at the same point, with the same
statuses. With the message category `callstacks`, the messages of the
statuses in the analysis from `main` are the same as with caching disabled,
the message of `two` and that of the postcondition with the callstack
`body :: message.c:25 <- main` included. With the delivery of messages
removed (a mutant of `Safety_delivery.deliver_write`), both comparisons
fail: the analysis with the hit completes, with `out = 8` at the end of
`main`, and the two messages of the hit are missing.

Hooks of red statuses, in `loop.c` with `-eva-slevel 10`: a hook that counts
its calls is called five times, as with caching disabled. Before the counts
were recorded, it was called four times: the hit ran it once for `mixed`
instead of twice. In `repeat.c`, where two red contexts form one write, it
is called three times, as with caching disabled. Order of the hooks and the
messages, in `abort-count.c` with `-eva-slevel 10` and the category `alarm`
set to abort: the check `mixed` fails at the first two iterations of the
loop. With caching disabled, the hook is called once, and the analysis
stops at the message of the invalid status; with the hit, the same. With
`Safety_part.record` changed to record each red context once, with its
count, at its first emission, as before this order was kept (a mutation,
reverted), the hit calls the hook twice before it stops.

**Open.**

- The entries are not saved with a session: the tables of supplied and
  produced entries are not marshalled. Cache state in a saved session is
  [issue #59](https://github.com/nyandrianinamamy/frama-c/issues/59).
- An entry taken from another analysis is a fixture device. The reset of
  Eva removes its alarms, and the delivery creates them again as a fresh
  emission would; the statuses of the annotations of the program are those
  of the second analysis only.
- The table of messages printed once is a state of the kernel that the
  reset of Eva does not clear. A message printed by the first analysis of
  the fixture, with the same kind at the same position, is not printed again
  by the second; the fixture runs the first analysis with the category
  `alarm` inactive where it compares messages.
- `-eva-stop-at-nth-alarm` is not replayed: when it is set, every supplied
  candidate is rejected
  ([A supplied entry is used only where a hit is supported](reuse-operation.md#a-supplied-entry-is-used-only-where-a-hit-is-supported)).
- Only the messages of statuses and the reports of alarms are replayed.
  Other messages printed during the analysis of a body refuse it: the
  special functions such as `Frama_C_show_each`, as `builtin`; `\warning`
  in an annotation, the messages preceded by
  `Body_access.read_message_history`, and the other messages printed once,
  such as the assumption of 2's complement for an overflow or a pointer
  comparison, as `side-table`. The exceptions are the feedback of
  partitioning and widening and the warning of locals escaping their
  scope, printed once per position without a refusal
  ([ordered effects](collector-effects.md#ordered-and-opaque-effects)),
  and the messages of an inactive category, which are not printed. A hit
  prints none of them; with caching disabled, the call prints the former
  only where the same text was not printed at the same position before, by
  the analysed call that produced the entry among others. The report of an
  evaluation that leads to bottom without alarms, a sign of a defect of
  Eva, is printed at each visit and is not replayed. When the status of the
  category of such a message differs between the producing call and the
  lookup of the hit, the entry is rejected; when a hook that the hit runs
  changes it after the lookup, the analysis stops after the delivery
  ([The settings that decide the alarms and messages are those of each hit](#the-settings-that-decide-the-alarms-and-messages-are-those-of-each-hit)).

## The owner of an alarm is that of an analysis of the body

**Claim.** The annotation of an alarm delivered at a hit has the owner that
an analysis of the body at the hit would give it: the emitter whose
registration of the alarm at that statement comes first. Eva registers the
alarms of a hit at the place in the sequence of registrations where the
analysis of the body would register them.

**Kind.** OCaml obligation, on the order of the registrations; it is not a
join, and lies outside the `RecordedWrite` law of
[A hit delivers the Safety part as recorded joins](#a-hit-delivers-the-safety-part-as-recorded-joins).

**Depends on.**
[The Safety part records the writes of the body](#the-safety-part-records-the-writes-of-the-body).

**Symbols.** `Alarms.register` in
[`alarms.ml`](../../../src/kernel/services/ast_data/alarms.ml),
`Alarmset.register`, `Alarmset.deliver`, `Safety_delivery.deliver`,
`Compute_functions.Make.compute_and_cache_call`.

**Argument (source inspection).** `Alarms.register` adds the annotation of
an alarm at a statement when it is absent, with the emitter of the call as
owner, and keeps the owner of an existing annotation. The owner is thus the
emitter of the first registration: another emitter, then Eva, gives the
other emitter; Eva, then the other emitter, gives Eva. A hit takes the place
of the analysis of the body in the analysis: the call hooks run before both,
and the delivery registers the alarms of the entry in the order in which
the body emitted them, the red contexts and the statuses in between. The
hooks that a delivered write runs, those of red statuses and of the kernel
on a new status, run at the same place in the sequence as for the analysed
body. A registration by another emitter, made before the call, after it, or
by one of these hooks, therefore comes at the same place relative to Eva's
in both.

**Evidence (executed).** `cache-safety.t`, `safety.c`. When another emitter
registers the division alarm first, the alarm has that emitter as owner and
Eva's status unknown on it, after a delivery of the Safety part as after an
analysis of `body`. When the other emitter registers it after the delivery,
Eva owns it.

**Open.** A registration made by a hook that the analysis of the body runs
and the delivery does not can come before Eva's in one and after it in the
other. The listeners of the logger and the clients of the hooks of
annotations and of property statuses refuse the body (`callback`,
[ordered effects](collector-effects.md#ordered-and-opaque-effects)); the
clients of the red status hooks run in both. No other such hook is known
in Frama-C.

## The passes after the analysis draw no conclusion where a hit skipped visits

**Claim.** A hit that delivers its Safety part saves no state at the
statements of the called function. It records the function in a state of the
analysis, reset with it. For a statement of a recorded function, the passes
run after the analysis draw no conclusion from the states saved there, which
are those of the analysed calls only: `Eval_annots.mark_unreachable` marks no
code annotation, no precondition of a call and no postcondition as
unreachable, and `Eval_annots.mark_green_and_red` gives no alarm and no
annotation a final status. `Export` generates no annotation in the function,
the summary of the analysis prints as reached only the statements with a
state, and gives the count with the statements of the function that have
none as an upper bound, and the server request `getDeadCode` lists none of
its statements. The statuses delivered by
the hit stay as delivered. The called function is the only one whose visits
a hit skips: an entry is refused for a body that may call a function that
has a body.

**Kind.** OCaml obligation.

**Depends on.**
[A hit delivers the Safety part as recorded joins](#a-hit-delivers-the-safety-part-as-recorded-joins)
and [Preconditions at a hit](#preconditions-at-a-hit).

**Symbols.** `Safety_delivery.skip_visits`, `Safety_delivery.visits_skipped`,
`Safety_delivery.visits_skipped_at`, `Safety_delivery.Skipped`,
`Compute_functions.Make.compute_and_cache_call`, `Eval_annots.unreached`,
`Eval_annots.mark_unreachable`, `Eval_annots.mark_green_and_red`,
`Export.generator`, `Export.main`, `Summary.reached`,
`Summary.unknown_reachability`, `Summary.print_coverage`,
`Summary.FunctionStats`, `Summary.compute_statuses`, `dead_code` in
[`ast_requests.ml`](../../../plugins/eva/src/server_api/ast_requests.ml),
`Supplied_entries.calls_a_body`, `Supplied_entries.add`,
`Supplied_entries.consumer_enabled`.

**Argument (source inspection).** `mark_unreachable` concludes that a
statement is unreachable when no state is saved before it, and
`mark_green_and_red` evaluates an alarm again on the states saved before its
statement, one per callstack, and emits valid or invalid when every one
agrees. At a hit, no state is saved for the call in the body of the called
function, so the states there do not cover the visits of the hit: a
statement reached through the hit only has no state, and the evaluation sees
the analysed calls only. The hit branch of `compute_and_cache_call` calls
`skip_visits` before the delivery; a hit whose preconditions leave no state
delivers nothing and is not recorded, since an analysis of the body would
then save no state either. `Eval_annots.unreached` is false at a statement of
a recorded function, and `mark_green_and_red` skips such a statement; the
statuses delivered by the hit are not touched. `Export.generator` skips the
statements of a recorded function, and `Export.main` warns instead of
annotating it. `Summary.reached` counts such a statement as reached, for the
coverage and for the counts of statuses; the statistics of the function are
computed again after a hit. The coverage so counted is an upper bound.
`Summary.print_coverage` prints it only when no statement is of unknown
reachability: otherwise, it prints the statements with a state as reached,
and adds, as an upper bound, the count with those that
`Summary.unknown_reachability` finds, the statements without a state of
the functions answered by a hit. Without a hit, the line is unchanged. The
statistic `stmt_coverage` (`Statistics`) and the coverage returned by the
server request of statistics (`progStmtCoverage`) keep the upper bound,
without a label. `dead_code` returns no list for a recorded
function. `Skipped` is a `State_builder.Set_ref` that depends on
`Self.state`: it is cleared with the results of Eva, at the start of each
analysis and on any change that resets them.

A hit skips the analysis of the functions that the body calls as well. A
stored body has no call: the producer refuses a body with a call
(`nested-call`), and `Supplied_entries.add`, used by `supply` and
`supply_produced`, raises `Invalid_argument` for a body that calls a
function that has a body, directly, through a pointer, or as the
constructor of a local initialisation. A call to a function without a body
has no statement to skip.

The restriction costs precision, for every call of a recorded function,
analysed or answered by a hit. An alarm or annotation there keeps the status
emitted during the analysis: unknown where `mark_green_and_red`, with caching
disabled, would emit valid or invalid from the final states of every
callstack. An annotation that no call reaches gets no unreachability status.
The fixture below shows no such difference; it follows from the argument.

**Readers inspected.** The readers of Eva's results at the end of or after
the analysis, at this revision:

- restricted as above: `Eval_annots.mark_unreachable`,
  `Eval_annots.mark_green_and_red`, `Export` (with option `-eva-annot`), the
  summary, the request `getDeadCode`;
- `Eval_annots.mark_invalid_initializers` reads the first statement of the
  entry point, which no hit answers;
- every supplied candidate is rejected as `consumer` when one of these
  plug-ins is loaded: Nonterm (dead code and non-termination reported from
  the absence of states), Metrics (coverage of statements and functions),
  the Markdown report (coverage, through `Eva.Results.is_reachable`), WP
  (states before a statement as hypotheses of its memory model based on Eva)
  and the constant propagation (values at statements);
- already rejected as `consumer` because they load Inout or From: the
  display of the final states (category `final-states`, which requires
  Inout), `Logic_inout`, and the plug-ins whose library depends on Inout or
  From, Reduc (assertions from the values at statements, given a valid
  status) among them;
- not restricted, and listed for issues #48 and #49: the values that
  `Eva.Results` returns at a statement of a recorded function, which cover
  the analysed calls only, and the readers built on them that report no
  status and no unreachability: the server requests of values
  (`getProbeInfo` reports a statement without a state as not evaluable),
  Studia, Dive, Aorai, the loop analysis, the callgraph and RTE (which reads
  the analysis status of a function);
- the table of red contexts and the report of red statuses
  (`-eva-report-red-statuses`) read the contexts delivered by the hit; the
  plug-ins that read property statuses, such as the SARIF output of the
  Markdown report, read the statuses of the first row, which the hit
  delivers and the passes no longer overwrite.

**Evidence (executed).** `cache-safety.t`, `passes.c`. The entry of
`body(1, 0)` from the analysis from `producer` answers the call at line 35
of `main`; `body(2, 1)` is analysed. Executed from `main`, the second call
divides 100 by y = 0 at line 13 when `v` reads a non-zero value, and reaches
the assertion `one` when `v` reads a non-zero value at line 10; the analysed
call never divides by zero and never reaches `one`. The statuses after the
analysis are those of caching disabled: the alarm is unknown, with its red
context in `body :: passes.c:35 <- main`, and `one` is valid with no
reachability status. In the reverse order (`reverse`, entry of `body(2, 1)`
from `producer_safe`, hit at line 44), the alarm is unknown, as with caching
disabled. From `no_return`, where `body(1, 0)` is a hit and `body(3, 1)`
never returns, the statuses are again those of caching disabled. Export
generates no annotation in `body`. The summary prints 12 statements of 15
reached, and up to 3 more through calls answered by the cache (100%);
caching disabled counts 14, and the loop at line 14, reached by no call, is
among the 3. With `Summary.print_coverage` changed to count no statement
of unknown reachability (a mutation, reverted), the same run prints 15
statements of 15 as reached, the upper bound as a measure. The
analysis from `producer`, without a hit, prints the usual line. After a
change of the entry point, `body` is no
longer recorded. `supply` refuses an entry for `outer`, which calls `body`.

With `Safety_delivery.skip_visits` changed to record nothing (a mutation,
reverted), the same programs and modes differ from caching disabled: from
`main`, the alarm gets the final status valid, and the statement at line 11
is marked unreachable; in the reverse order, the alarm gets the final
status invalid; from `no_return`, the alarm is valid, and the statement at
line 11 and the function `body` are marked unreachable. Export generates
seven annotations in `body`, all valid, among them `\false` at lines 10
and 14. The summary prints 12 statements of 15 as reached, without the
upper bound.

The request `getDeadCode`, the warning of `Export.main` (option
`-eva-annot`; the test calls `Export.generator`) and the rejection when the
Markdown report, WP or the constant propagation is loaded rest on source
inspection; the rejection when Nonterm or Metrics is loaded is executed.

**To lift the restriction.** Issue #48 must make a hit deliver, for its
callstack, the statements its call reaches, so that `mark_unreachable` can
mark the others, and the states of these statements, or the outcome of the
refinement recorded in the entry (issue #49), so that `mark_green_and_red`
can evaluate an alarm on the visits of every call. The record of skipped
functions can then be removed for the passes that the delivered data serve,
and the rejections of Nonterm, Metrics, the Markdown report, WP and the
constant propagation lifted once the readers above see the delivered states.
Once a stored body may call other functions (issues #50 and #51), the entry
must carry the functions whose visits its hit skips, so that a hit records
them all.

## A change of the current project refuses the recordings in progress

**Claim.** A recording belongs to the project that is current when it starts.
A change of the current project while a recording is in progress, of the
Safety part or of the collector, refuses every recording in progress with
the reason `project-switch`, even if the project changes back before the end
of the recording, and even if the change is made in a hook of another
change of project: no entry is stored for these bodies. A write of the
Safety part made after such a change is not recorded.

**Kind.** OCaml obligation, of Eva and of the kernel: the count of
`Project.current_changes` is incremented by every operation that changes
the current project.

**Depends on.**
[Refusal and reporting](body-access.md#refusal-and-reporting).

**Symbols.** `Project.current_changes`, `Project.force_set_current`,
`Project.remove`, `Project.remove_all`, `Project.create`,
`Project.load_projects` in
[`project.ml`](../../../src/lib/project/project.ml), `Body_access.capture`,
`Safety_part.capture`, `Safety_part.record`, `Body_access.Result.refusal`.

**Argument (source inspection).** The current project is the top of the
stack of projects of the kernel. The operations that change the top count
the change before they run any hook: `force_set_current`, reached from
`set_current`, from `Project.on` on entry and on exit, and from the loading
of projects; `remove` when it removes the current project; `remove_all`;
and `create` when there is no project. The kernel does not run the hooks of
the change of project for a change made during one of these hooks, but it
counts it. Each capture of the collector keeps the project and the count at
its start, and adds `Project_switch` to its refusals when the count or the
current project differs at its end. Every capture in progress compares its
own start, so the bodies whose analysis contains that of the current one
are refused as well. The producer stores no body with a refusal.
`Safety_part.record` compares the project and the count at the start of the
recording with the current ones at each write, and refuses instead of
recording when either differs. The count is a value of the process, not a
state of a project: it is neither saved nor loaded with a session. Since
every change of the current project increments the count, the comparison
of the count at the end of `Body_access.capture` decides the refusal; the
comparisons of the project, and the comparison at each write of the Safety
part, refuse no body that it does not refuse. No test tells them apart
from it; only the removal of the comparison of the count alone, and of all
the comparisons together, were run.

**Evidence (executed).** `cache-safety.t`: a hook of red statuses enters a
second project with `Project.on` the first time it runs, during the analysis
of `body` from `producer`, and sets a red status there. The calls of `body`
and of `producer` read `collector: refused (project-switch)`, the statistic
`collector-refused-project-switch` is 1 for each, and no entry is produced.
The analysis from `main` then has no candidate, and its tables are those of
the run with caching disabled and the same hook. With the comparisons of
the project removed from `Body_access.capture` and `Safety_part.record` (a
mutation, reverted), the entry is stored with the red context set in the
second project, and the hit delivers it in the first: the tables of `main`
have a red context of the reachability of the statement at line 8 of
`body`, which caching disabled does not have. With the comparison of the
count removed alone, `body` is still refused, by the comparison of the
project at its write in the second project, and `producer` is refused for
another reason (`sweep`).

A change made in a hook of another change, in `cache-safety.t`: the
analysis from `producer` runs in a hook of the change of project to a copy
of the first project. The first time it runs, a hook of red statuses enters
the first project with `Project.on` and leaves it, without writing there.
The calls of `body` and of `producer` read
`collector: refused (project-switch)`, and no entry is produced. The
analysis from `main`, in the copy, has no candidate, and its tables are
those of the run with caching disabled in the same setting, as are those
of the first project, where Eva wrote nothing. With the comparison of the
count removed alone from `Body_access.capture` and `Safety_part.record` (a
mutation, reverted), the call of `body` reads `collector: would-store`, its
entry is produced, and the second call of `body` in the copy is a hit. The
tables are then still equal to those of the run with caching disabled:
the test shows the refusal by the verdict and the count of entries.

## The settings that decide the alarms and messages are those of each hit

**Claim.** An entry holds the alarms, statuses and messages that an
analysis of the body would emit at a hit only if the settings that decide
them, in force when the analysis of the body that produced the entry
started, are in force at the hit:
- the options of the kernel and of Eva that decide which alarms and
  statuses are emitted: the `-warn-*` options of the kernel, such as
  `-warn-signed-overflow`, and the `-eva-warn-*` options of Eva, such as
  `-eva-warn-copy-indeterminate`;
- the status of every warning category of Eva and of the kernel
  (`-eva-warn-key`, `-kernel-warn-key`), which decides the action of its
  messages (none, a feedback, a warning, an error or an abort), apart from
  the category `alarm` of Eva.

The lookup of a produced entry checks the second: it rejects the entry
(`warn-categories`) when the status of a category differs from its status
when the analysis of the body started. The options, the categories of an
entry given to `Supplied_entries.supply`, and a change made by a hook on
calls at the call of the hit, after its lookup, are owed by the supplier.
A violation can hide an alarm or a message, and with a category set to
abort, change the state at the end of the call.

**Kind.** OCaml obligation: the check of the lookup for the categories of
a produced entry; for the rest, owed by the supplier of an entry
(`Supplied_entries.supply` and `supply_produced`).

**Depends on.**
[A hit delivers the Safety part as recorded joins](#a-hit-delivers-the-safety-part-as-recorded-joins).

**Symbols.** `Body_access.warn_categories`, `Body_access.capture`,
`Cache_entry.dependencies`, `Supplied_entries.Lookup.find`,
`Supplied_entries.supply`, `Supplied_entries.supply_produced`,
`Kernel.SignedOverflow`, `Evaluation.Make.handle_integer_overflow`,
`set_warn_status`, `get_all_warn_categories_status` and `logwith` in
[`log.ml`](../../../src/lib/utils/log.ml),
`Cvalue_callbacks.apply_call_hooks`,
`Compute_functions.Make.compute_and_cache_call`.

**Argument (source inspection).** The Safety part records the writes of an
analysis of the body with the options of the producing analysis. An option
that turns a class of undefined behaviour into alarms changes these writes:
the same body emits an alarm under one setting and none under the other.
The delivery makes the recorded writes only, so an entry produced with
fewer alarms hides those that the analysis that uses it would emit.

A hit prints, through the logger, the messages of the statuses and the
reports of the alarms of its entry, all of the category `alarm` of Eva: the
action of this category in force at the hit applies, as for an analysed
call. The other messages of the body are not recorded and not printed by a
hit; for instance, the assumption of 2's complement for an overflow
(category `signed-overflow`) in a body analysed with the category inactive.
When the category of such a message is set to abort at the hit, an
analysis of the body stops at the message, and the call has no state at
its end, where the hit returns the exit states of the entry. Only the
status of a warning category decides an action; a message category
(`-eva-msg-key`) decides whether a message is printed, and a hit prints
none of these messages of the body.

The status of a category can change between the producing call and the
hit: the two analyses are run with different settings; a hook changes a
category during the analysis, by `set_warn_status` or by setting
`-eva-warn-key`; or a later stage of the command line (`-then`) changes it.
`Body_access.capture` reads the status of every category of the kernel and
of Eva, but `alarm`, when the analysis of the body starts; the producer
stores it with the entry, and the lookup of the supplied entries reads it
again and compares. A change made before the lookup, by any of these means,
is seen. The status is read at the start of the body: if a client of the
red status hooks, which a body admits, changes a category during the body,
the earlier messages of the body ran under the status read. A hit runs
hooks after its lookup: the hooks on calls; the hooks on statuses, the red
status hooks and the listeners of the logger, when it prints the line of
the call and evaluates the preconditions; and the red status hooks during
the delivery. `Call_cache` reads the status of the categories when the
lookup of the supplied entries starts, and after the delivery, the hit
compares it with the current status (`check_warn_categories` in
`Compute_functions`): when one differs, the analysis stops with an error,
since the hit cannot tell what an analysis of the body would do under the
new status. The tables then hold the whole Safety part of the entry, where
an analysis of the body that stops at a message holds the writes made
before it. A change undone before the end of the delivery is not seen. A
`-once` category becomes inactive after its first message; the lookup then
rejects the entries produced before, which is conservative.

**Evidence (executed).** `cache-safety.t`.

- `overflow.c`, premise violated on purpose. The entry of `body(1)` is
  produced with `-no-warn-signed-overflow` and used by an analysis with
  `-warn-signed-overflow`, both with the category `signed-overflow`
  inactive: the hit at line 19 delivers no alarm, where the analysis with
  caching disabled emits the overflow alarm at line 8 with an invalid
  status and a red context. With the category active, the assumption of 2's
  complement is printed once, and the collector refuses the body
  (`side-table`).
- `overflow.c`, across analyses. The entry is produced with the category
  inactive, and looked up with the category set to abort: the call reads
  `lookup: rejected (entry 1: warn-categories); execution: interrupted`,
  the analysis stops at the overflow, and the tables equal those of the
  analysis with caching disabled.
- `same.c`, within one analysis. The first call of `body` is analysed with
  the category inactive, and its entry is stored; a hook on the status of
  the assertion in `other` supplies it and sets the category to abort. The
  second call reads `lookup: rejected (entry 1: key-differs), rejected
  (entry 2: warn-categories)`, and stops at the overflow, as with caching
  disabled. With the comparison of `Supplied_entries.Lookup.admit` removed
  alone, both runs hit and give `out = 8`.
- `overflow.c`, after the lookup. The entry is produced with the category
  inactive, and in the analysis that uses it, a hook on calls sets the
  category to abort at the call of `body`, after the lookup. The call reads
  `lookup: hit (entry 1)`, then the analysis stops with `the status of the
  warning categories signed-overflow changed during the hit on body`. The
  analysis with caching disabled stops at the overflow, and the tables are
  equal: the entry holds no alarm. With the call of `check_warn_categories`
  removed alone (a mutation run), the hit prints nothing and gives
  `out = 8`, and only this section of the test fails. The other hooks that
  the hit runs after its lookup reach the same comparison; no test runs
  them.

**Open.**

- The options that decide the alarms are not checked. The entries saved
  with a session
  ([issue #59](https://github.com/nyandrianinamamy/frama-c/issues/59))
  cross analyses: they must store these options and the status of the
  categories with the entry, and compare them at the lookup in the
  analysis that loads them.
- A hit stops the analysis when a hook that it runs changes a category,
  where an analysis of the body goes on unless the body prints a message of
  that category under an action that stops. Analysing the body instead
  would announce the call to the hooks on calls a second time, as `Body`
  after `Reuse`: the callwise clients of From and Inout push a frame for
  `Body` only, and every client would see two calls.

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
for x = 1, whose Safety part gives the check `one` a valid status, answers
the call `pre(1)` at line 18, where g = 0. The precondition `positive` is
reported invalid at line 18, its instance at that call is invalid and has
the red context of the call, and no state reaches the end of `main`. Before
the passes at the end of the analysis, `one` is never tried: the hit
delivered nothing. The passes then mark `one` unreachable, as with caching
disabled, and the statuses are those of caching disabled. With the exit
state used, the test fails: `out = 5` holds at the end of `main`. With the
Safety part delivered at that hit (a mutant of the hit branch), the test
fails: `one` is valid before the passes.

**Open.** A precondition that narrows the input without emptying it is not
applied to the entry.
