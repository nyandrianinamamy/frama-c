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
postcondition, and each red context that it adds are recorded once, in the
order of their first emission. Each write keeps its statement or property,
its status, its emitter or its text, and the calls between the body and the
point of emission (its frames). A red context also keeps the number of times
the body set it. The checks of the `requires` clauses of the called function
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
refuses the body as `side-table`. A write equal to one already recorded is
not added again: the tables below join a value with itself into the same
value. Two red contexts that differ only by their count are the same write,
whose count is the sum.

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
loop, is recorded once with the count 2. With caching disabled, the Safety
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
| annotations of alarms (`Alarms`) | statement, alarm | absent, or present with its owner, the emitter that registered it first | the existence of the annotation that states the alarm; its statuses are those of the first row, one per emitter | presence by or; a later registration keeps the owner |
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
status of that emitter on the annotation. The existence and the owner of the
annotation are thus separate from the statuses: an alarm that another
emitter registered first keeps that emitter as owner, and Eva emits its
status on it and registers nothing of its own, in a delivery as in a fresh
emission. `Alarm_cache.memo` adds the alarm and reports it if it is absent,
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
(`Supplied_entries.supply`); for an entry used by another analysis than the
one that produced it, the supplier also owes the premise of
[The options that decide the alarms are those of the analysis that uses the entry](#the-options-that-decide-the-alarms-are-those-of-the-analysis-that-uses-the-entry).
The [hit theorem](hit.md#hit-soundness) states the coverage of Safety for
concrete executions under its own premises; whether Eva's statuses meet them
is the open premise of the Exit claim as well.

*Other positions.* `deliver` writes at the positions of the saved writes
only. The hooks that a write triggers, the updates of the kernel on a new
status and the hooks of `Red_statuses`, are those of a fresh emission; the
hooks of red statuses run once for each time the body set the red context,
as `Red_statuses.register_hook` promises.

*Repeated and nested work.* A body that emits the same write at several
visits records it once, which the idempotence of the joins makes equivalent;
the count of a red context keeps the number of calls of the hooks. A hit
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
instead of twice.

Owner of an alarm, in `safety.c`: another emitter registers the division
alarm first. After a delivery of the Safety part, as after an analysis of
`body`, the alarm has that emitter as owner and Eva's status unknown on it.

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

## The passes after the analysis draw no conclusion where a hit skipped visits

**Claim.** A hit that delivers its Safety part saves no state at the
statements of the called function. It records the function in a state of the
analysis, reset with it. For a statement of a recorded function, the passes
run after the analysis draw no conclusion from the states saved there, which
are those of the analysed calls only: `Eval_annots.mark_unreachable` marks no
code annotation, no precondition of a call and no postcondition as
unreachable, and `Eval_annots.mark_green_and_red` gives no alarm and no
annotation a final status. `Export` generates no annotation in the function,
the summary of the analysis counts its statements as reached, and the server
request `getDeadCode` lists none of its statements. The statuses delivered by
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
computed again after a hit. `dead_code` returns no list for a recorded
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
generates no annotation in `body`. The summary counts 15 statements of 15
as reached, where caching disabled counts 14: the loop at line 14, reached
by no call, is counted. After a change of the entry point, `body` is no
longer recorded. `supply` refuses an entry for `outer`, which calls `body`.

Before the restriction, with the analyzer at revision `5c7f2e1fc5` and the
same fixture, the runs differed from caching disabled: from `main`, the
alarm got the final status valid and `one` was marked unreachable; in the
reverse order, the alarm got the final status invalid; from `no_return`, the
alarm was valid, and `one` and the postcondition were marked unreachable.
Export generated seven annotations in `body`, all valid, among them
`\false` at lines 10 and 14. The summary counted 12 statements of 15.
`supply` accepted the entry for `outer`.

The request `getDeadCode` and the rejection when the Markdown report, WP or
the constant propagation is loaded rest on source inspection; the rejection
when Nonterm or Metrics is loaded is executed.

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
of the recording: no entry is stored for these bodies. A write of the Safety
part made while another project is current is not recorded.

**Kind.** OCaml obligation.

**Depends on.**
[Refusal and reporting](body-access.md#refusal-and-reporting).

**Symbols.** `Body_access.capture`, `Body_access.observe_project_changes`,
`Body_access.project_changes`, `Project.register_after_set_current_hook`,
`Safety_part.capture`, `Safety_part.record`, `Body_access.Result.refusal`.

**Argument (source inspection).** At its first recording, the collector
registers a hook of the kernel that counts the changes of the current
project; `Project.on` changes it twice, on entry and on exit, and the hook,
registered with `~user_only:false`, runs for both. Each capture keeps the
project and the count at its start, and adds `Project_switch` to its
refusals when the count or the current project differs at its end. Every
capture in progress compares its own start, so the bodies whose analysis
contains that of the current one are refused as well. The producer stores
no body with a refusal. `Safety_part.record` compares the project of the
recording with the current one at each write, and refuses instead of
recording when they differ. The kernel does not run the hooks for a change
made by another hook of the change of project: a change made and undone
within such a hook is not counted, but a write of the Safety part in that
window is still caught by the comparison at the write.

**Evidence (executed).** `cache-safety.t`: a hook of red statuses enters a
second project with `Project.on` the first time it runs, during the analysis
of `body` from `producer`, and sets a red status there. The calls of `body`
and of `producer` read `collector: refused (project-switch)`, the statistic
`collector-refused-project-switch` is 1 for each, and no entry is produced.
The analysis from `main` then has no candidate, and its tables are those of
the run with caching disabled and the same hook. Before the refusal, with
the analyzer at revision `5c7f2e1fc5` and the same fixture, the entry was
stored with the red context set in the second project, and the hit
delivered it in the first: the tables of `main` had a red context of the
reachability of the first statement of `body`, which caching disabled does
not have.

## The options that decide the alarms are those of the analysis that uses the entry

**Claim.** An entry used by an analysis other than the one that produced it
holds the alarms and statuses of that analysis only if the options of the
kernel and of Eva that decide which alarms and statuses are emitted are
equal in both: the `-warn-*` options of the kernel, such as
`-warn-signed-overflow`, and the `-eva-warn-*` options of Eva, such as
`-eva-warn-copy-indeterminate`. The supplier of the entry owes this
equality. Within one analysis the options do not change, and the lookup
checks nothing.

**Kind.** OCaml obligation, owed by the supplier of an entry
(`Supplied_entries.supply` and `supply_produced`); nothing in Eva enforces it.

**Depends on.**
[A hit delivers the Safety part as recorded joins](#a-hit-delivers-the-safety-part-as-recorded-joins).

**Symbols.** `Supplied_entries.supply`, `Supplied_entries.supply_produced`,
`Kernel.SignedOverflow`.

**Argument.** The Safety part records the writes of an analysis of the body
with the options of the producing analysis. An option that turns a class of
undefined behaviour into alarms changes these writes: the same body emits an
alarm under one setting and none under the other. The delivery makes the
recorded writes only, so an entry produced with fewer alarms hides those
that the analysis that uses it would emit.

**Evidence (executed, premise violated on purpose).** `cache-safety.t`,
`overflow.c`: the entry of `body(1)` is produced with
`-no-warn-signed-overflow` and used by an analysis with
`-warn-signed-overflow`. The hit at line 19 delivers no alarm, where the
analysis with caching disabled emits the overflow alarm at line 28 with an
invalid status and a red context. The test documents the current behaviour,
not a guarantee.

**Open.** The entries saved with a session
([issue #59](https://github.com/nyandrianinamamy/frama-c/issues/59)) cross
analyses, and must enforce this premise, for instance by storing the
options with the entry and rejecting it when they differ.

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
