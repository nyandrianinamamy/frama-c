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
sequence, in the order of emission. An alarm or a status is recorded at its
first emission only. A message and a red context are recorded at each
emission, in their place among the other writes. Each write keeps its
statement or property, its status, its emitter
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
refuses the body as `side-table`. An alarm or a status equal to one already
recorded is not added again: the tables below join a value with itself into
the same value, and `Property_status.emit ~distinct:true` emits nothing and
runs no hook for a status equal to the previous one
(`merge_distinct_emitted`). A message is added at each emission: the logger
consults its history at each one, which its observers see, before it
decides whether to print the text. A red context runs the hooks of red
statuses each time it is set, so it is added at each emission.

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
stores. `Recursion.mark_unknown_requires` runs at a recursive call made by
the body, which the collector refuses (`recursion`): the called function is
active.
`Logic_inout.check_fct_assigns` runs in the callwise hook of From under
`-from-verify-assigns`, outside the observation: its statuses are not part
of the Safety part, and at a hit the restoration of the From part runs it
again in the state of the call
([The From part](cache-parts.md#the-from-part)).
`Eval_annots` runs after the analysis, and `Eva_results` and `Export` do not
run during one. The checks of the `requires` clauses of a body belong to its
call site: `Safety_part.record` records no write while
`Body_access.at_call_site` runs one (`Body_access.checking_call_site`).
Since the producer also refuses a callee with `requires` clauses
(`preconditions`), every write of a produced entry of a body without a call
has empty frames.

Since [issue #50](https://github.com/nyandrianinamamy/frama-c/issues/50),
the producer also stores bodies with calls. The Safety part of such a body
is incomplete. It holds the writes that the hits of its calls deliver, with
the call as frame, and the checks of the preconditions at these hits, which
run in the body. It holds none of the writes made in the bodies analysed
afresh during its analysis, nor the checks of their `requires` clauses:
`Safety_part.record` records a write in the innermost recording only, and
the part of each such body holds its own writes. The lookup rejects every
entry whose body contains a call other than a direct call to a display
directive (`Frama_C_show_each*`, `Frama_C_domain_show_each*`), and no hit
delivers such a part
([Composition along the observed path](nested-calls.md#composition-along-the-observed-path)).
A candidate whose key matches reads `missing-part` when it lacks a part
whose consumer is enabled, which From and Inout do not give for a call that
made a call: the entries of `outer` in `nested.c` of `cache-parts.t` read
`missing-part` under `-calldeps`. Otherwise it reads `nested-delivery`: the
entry of `leaf` in `dead-call.c`, whose producing call did not make its
call and which has both parts, reads `nested-delivery`.

**Evidence (executed).** In `cache-safety.t`, the entry of `body` produced by
the analysis from `producer`, at x = 1 and y = 0, has seven writes, all with
empty frames: the red context, the invalid status and the message of the
assertion `two`, the red context of the division alarm, the alarm with an
unknown status, and the valid status and the message of `ok`. In `loop.c`,
the red context of the check `mixed`, which fails at two iterations of the
loop, is recorded at each failure: the first before the invalid status and
its message, the second after them. In `repeat.c`, the check `never` fails
at the three iterations: after the first, its status is the one already
recorded, and its red context and its message are recorded at each
iteration. With caching disabled, the Safety
part observed for each call of `pre` is empty, although the evaluation of its
`requires` clause emits an invalid status at the second call. This check
runs while the recording of `main` is current (`Body_access.at_call_site`);
with the test of `checking_call_site` removed from `Safety_part.record` (a
mutation, reverted), the part of `pre` holds the valid status of the
precondition at the first call and its red context at the second. In
`enclosing.c`, the part of `parent` is empty when
the analysis of `parent` analyses `child`, and holds the red context, the
invalid status and the message of the check `big` of `child`, with the call
of `child` as frame, when a hit answers that call.

**Open.**

- The iterator still consults the history of the alarms emitted
  (`Alarmset.already_emitted`) and refuses as `side-table`
  ([Side tables and recorded joins](body-access.md#side-tables-and-recorded-joins)).
  A body analysed after one of its own alarms was emitted gives no entry; the
  reference run of `cache-safety.t` shows it for the second call of `body`.
- The Safety part of a body with a call is incomplete, and no hit delivers
  it. Delivery at a hit on such a body needs the writes of every child at
  its call site, those of the children analysed afresh included, and the
  marking of every function whose visits the hit skips
  ([Composition along the observed path](nested-calls.md#composition-along-the-observed-path)).
  The fixture delivers writes with a frame added by hand only.
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
`~once:true`, as the body does, at each occurrence recorded: the logger
consults its history at each one, prints the text only if it has not
printed the same text, of the same kind, at the same position before, and
applies the action of the category `alarm` (abort, error) when it prints it.
`Red_statuses.add_red_context` adds the current callstack to the set and runs
the hooks of red statuses. The
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
only. The hooks that a write triggers are those of a fresh emission: the
hooks of the kernel on a new property, on a new status and on a change of
the annotations, the hooks of red statuses, and the listeners and the
observers of the history of the logger. A hit is admitted only when no
client that is not audited is registered on these hooks
([A hit runs no client that is not audited](#a-hit-runs-no-client-that-is-not-audited)),
and the audited clients write nothing at these positions. The hooks of red
statuses have no audited client, so no client of them runs at an admitted
hit. The writes are delivered in the order of the sequence, which is the
order of the analysis of the body: an action of a category that stops the
analysis at a message finds the same writes made before it.

*Repeated and nested work.* A body that emits the same alarm or status at
several visits records it once, which the idempotence of the joins makes
equivalent: a later equal write changes no value and runs no hook of the
kernel. Each message and each red context is kept in the sequence at each
emission, so that the logger makes its test at each occurrence, as in the
analysis of the body. A hit
inside a body under analysis records its delivered writes in that body
through the same functions, with the frames of the hit. The entry of a body
with a call is rejected at lookup, with `nested-delivery`, or before with
`missing-part` when it lacks a part whose consumer is enabled: its part is
incomplete
([The Safety part records the writes of the body](#the-safety-part-records-the-writes-of-the-body)).

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

Repeated writes. In `loop.c` with `-eva-slevel 10`, the hit sets both red
contexts of `mixed`, and the tables are those of caching disabled. In
`repeat.c`, the message of `never` is recorded at each of the three
iterations; the observer of the history of the collector, an audited client,
counts 3 consultations of the history at the hit, as with caching disabled.
With `Safety_part.record` changed to record a message at its first emission
only (a mutation, reverted), it counts 1 at the hit. Order of the red
contexts and the messages, in `abort-count.c` with `-eva-slevel 10` and the
category `alarm` set to abort: the check `mixed` fails at the first two
iterations of the loop. With caching disabled, the analysis sets the first
red context and stops at the first message of the invalid status; with the
hit, the same, with the same tables. The order of the red contexts relative
to the messages is seen by a client of the hooks of red statuses only, and
none runs at an admitted hit: earlier versions of this test counted the
calls of such a client, which now rejects the entry.

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
  The special functions such as `Frama_C_show_each` refuse the body as
  `builtin`, and `\warning` in an annotation as `side-table`. A message
  printed once reads the history of the logger, and refuses the body as
  `side-table`: the messages preceded by
  `Body_access.read_message_history`, the assumption of 2's complement for
  an overflow, a pointer comparison. The exceptions are the feedback of
  partitioning and widening and the warning of locals escaping their
  scope, printed once per position without a refusal
  ([ordered effects](collector-effects.md#ordered-and-opaque-effects)),
  and the messages of an inactive category, which are not printed. A hit
  prints none of these other diagnostics of the body, only the recorded
  messages of its statuses and the reports of its alarms; with caching
  disabled, the call prints the former only where the same text was not
  printed at the same position before, by the analysed call that produced
  the entry among others. A message printed at each occurrence reads no
  history: it neither refuses the body nor is printed by a hit. The report
  of an evaluation that leads to bottom without alarms, a sign of a defect
  of Eva, is one; so are the messages of progress and of debugging. A
  listener of the logger would see the difference, and rejects every entry
  ([A hit runs no client that is not audited](#a-hit-runs-no-client-that-is-not-audited));
  the table of messages of the kernel, an audited client, keeps it. When
  the status of the category of such a message differs between the
  producing call and the lookup of the hit, the entry is rejected
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
the body emitted them, the red contexts and the statuses in between. A
registration by another emitter, made before the call or after it,
therefore comes at the same place relative to Eva's in both. A hit is
admitted only when no client that is not audited is registered on the hooks
that a delivered write runs or that the analysis of the body runs
([A hit runs no client that is not audited](#a-hit-runs-no-client-that-is-not-audited)),
and no audited client registers an alarm: no registration is made between
Eva's during the delivery.

**Evidence (executed).** `cache-safety.t`, `safety.c`. When another emitter
registers the division alarm first, the alarm has that emitter as owner and
Eva's status unknown on it, after a delivery of the Safety part as after an
analysis of `body`. When the other emitter registers it after the delivery,
Eva owns it.

**Open.** A registration made by a hook that the analysis of the body runs
and the delivery does not could come before Eva's in one and after it in
the other. The clients of the hooks listed in
[A hit runs no client that is not audited](#a-hit-runs-no-client-that-is-not-audited)
refuse the body during which they run (`callback`,
[ordered effects](collector-effects.md#ordered-and-opaque-effects)), and
reject every supplied entry while they are registered. No other such hook
is known in Frama-C.

## The passes after the analysis draw no conclusion where the queries do not see the points of a hit

**Claim.** A hit that delivers its Safety part saves no state at the
statements of the called function, and records the points its body
reaches, where its callstack answers the state top
([Reach at a hit](reach.md)): every hit delivers a Reach part, since the
lookup rejects an entry without one (`missing-points`). When the store of
the cvalue domain saves no state (`-eva-no-results-domain cvalue`), the
queries do not see these points
([Reach at a hit](reach.md#the-queries-see-the-points-reached-by-a-hit-with-the-state-top)),
and the hit records the function as of unknown reachability, in a state of
the analysis, reset with it. For a statement of such a function, the
passes that read the absence of a state as unreachable code draw no
conclusion: `Export` generates no annotation in the function, and the
server request `getDeadCode` lists none of its statements. Under that
option, when the cvalue domain is the only domain, the other passes draw
no conclusion at a statement of a function that the analysis calls, with
or without a hit: `Eval_annots.mark_unreachable` marks none of them
unreachable, `Eval_annots.mark_green_and_red` gives none a final status,
and the summary counts each as reached. A function that the analysis never
calls keeps its conclusions (its statements are unreachable), and another
domain whose store saves states can still give a final status. The statuses delivered by
the hit stay as delivered. The called function is the only one whose
visits a hit skips: no hit is admitted on a body with a call. The passes
after a hit whose points the queries see are the subject of
[The passes after the analysis read the points reached by hits](reach.md#the-passes-after-the-analysis-read-the-points-reached-by-hits).
The hit also records the function among those whose visits a hit
skipped, in a state of the analysis, reset with it, saved with the
session and kept with the results that `Eva_results` takes and installs
again; From, Inout, Pdg and Studia read this record
([Results computed from statement states are refused after a hit](cache-parts.md#results-computed-from-statement-states-are-refused-after-a-hit)).

**Kind.** OCaml obligation.

**Depends on.**
[A hit delivers the Safety part as recorded joins](#a-hit-delivers-the-safety-part-as-recorded-joins)
and [Preconditions at a hit](#preconditions-at-a-hit).

**Symbols.** `Reach_delivery.deliver`, `Reach_delivery.reach_unknown_of`,
`Reach_delivery.Unknown`, `Cvalue_domain.State.Store.is_computed`,
`Safety_delivery.skip_visits`, `Safety_delivery.visits_skipped`,
`Safety_delivery.Skipped`, `Compute_functions.Make.compute_and_cache_call`,
`Results.is_reachable`, `Eval_annots.mark_unreachable`,
`Eval_annots.mark_green_and_red`, `Eval_annots.eval_by_callstack`,
`Export.generator`, `Export.main`, `Summary.compute_fun_stats`,
`Summary.print_coverage`, `Summary.FunctionStats`,
`Summary.compute_statuses`, `dead_code` in
[`ast_requests.ml`](../../../plugins/eva/src/server_api/ast_requests.ml),
`Supplied_entries.calls_a_body`, `Supplied_entries.supply`,
`Supplied_entries.has_nested_call`, `Supplied_entries.Lookup.admit`,
`Supplied_entries.consumer_enabled`.

**Argument (source inspection).** The hit branch of
`compute_and_cache_call` calls `skip_visits`, then delivers the Safety
part, then the Reach part of the entry, which the lookup requires.
`Reach_delivery.deliver` records the function as of unknown reachability
when its states are saved and the store of the cvalue domain saves none
(`Cvalue_domain.State.Store.is_computed`). A hit whose preconditions leave
no state delivers nothing and records nothing, since an analysis of the
body would then save no state either. Under
`-eva-no-results-domain cvalue`, with no other domain, the store answers
`Top` at every point of a function that the analysis calls:
`Results.is_reachable` holds at each of its statements, and the cvalue
state at its start is the top state (`Ok Cvalue.Model.top`).
`mark_unreachable`, which concludes that a statement is unreachable when
`Results.is_reachable` is false there, marks none of them;
`mark_green_and_red` evaluates an alarm through `eval_by_callstack`, which
takes the states before the statement by callstack, gets none, and answers
`Unknown` from the empty fold, so that nothing is emitted; the summary
counts the statements where `Results.is_reachable` holds
(`Summary.compute_fun_stats`), all those of a called function. These conclusions are the same
with caching disabled, and the three passes have no test of unknown
reachability. `Export.generator` asserts `\false` at a statement without a
callstack, and `dead_code` lists such a statement as unreachable: under
that option, they do so at every statement of a called function with
caching disabled (see the open items of
[Reach at a hit](reach.md#the-queries-see-the-points-reached-by-a-hit-with-the-state-top)).
In a function of unknown reachability, `Export.generator` skips the
statements, `Export.main` warns instead of annotating it, and `dead_code`
returns no list. `Skipped`, the functions answered by a hit that delivers
its Safety part, serves the statistics of the function, computed again
after such a hit (`Summary.FunctionStats`, through
`Safety_delivery.delivered`), and the readers of the results computed
from statement states (`Safety_delivery.complete`). `Unknown` and `Skipped` are
`State_builder.Set_ref` states that depend on `Self.state`: they are
cleared with the results of Eva, at the start of each analysis and on any
change that resets them.

A hit skips the analysis of the functions that the body calls as well. No
hit is admitted on a body with a call, by two checks.
`Supplied_entries.supply` raises `Invalid_argument`, before any lookup, for
a body that may call a function that has a body, directly, through a
pointer, or as the constructor of a local initialisation. The lookup
rejects every entry whose body contains a call other than a direct display
directive (`nested-delivery`), produced entries included: since issue #50
the producer stores bodies with calls, and `supply_produced` does not check
the calls. `nested-delivery` is the last check of a candidate: an entry
that lacks a part whose consumer is enabled reads `missing-part` before, as
the entries of `outer` in `nested.c` of `cache-parts.t` do. The check of
`supply` comes first: an entry that it refuses is never a candidate. A call
to a function without a body has no statement to skip, and its entry is
rejected all the same.

Export and the server requests meet a function of unknown reachability
only under `-eva-no-results-domain cvalue`, where caching disabled reports
the statements of every called function unreachable. In `cache-reach.t`,
a process that loads the server plug-in and the session saved after a
hit under that option gets no statement of `body` from the request of
dead code. The server requests also meet hits in the process of the
analysis: the client of the server on the changes of annotations
(`Kernel_ast`) is audited at the lookup
([A hit runs no client that is not audited](#a-hit-runs-no-client-that-is-not-audited)),
and the collector still refuses a body during which it runs, one that
registers an alarm.

**Readers inspected.** The readers of Eva's results at the end of or after
the analysis, at this revision:

- reading the points reached by hits
  ([Reach at a hit](reach.md#the-passes-after-the-analysis-read-the-points-reached-by-hits)):
  `Eval_annots.mark_unreachable`, `Eval_annots.mark_green_and_red`,
  `Export` (with option `-eva-annot`), the summary, the request
  `getDeadCode`; Export and `getDeadCode` skip a function of unknown
  reachability, as above;
- `Eval_annots.mark_invalid_initializers` reads the first statement of the
  entry point, which no hit answers;
- every supplied candidate is rejected as `consumer` when one of these
  plug-ins is loaded: Nonterm (dead code and non-termination reported from
  the absence of states), Metrics (coverage of statements and functions),
  the Markdown report (coverage, through `Eva.Results.is_reachable`), WP
  (states before a statement as hypotheses of its memory model based on Eva)
  and the constant propagation (values at statements);
- the results by function of From and Inout, computed from the states
  saved at statements, and their readers: From, Inout and Pdg refuse them
  after a hit, and every supplied candidate is rejected as `consumer` while
  Pdg, Reduc (assertions from the values at statements, given a valid
  status) or Studia, or a plug-in that loads one of them, is loaded
  ([Results computed from statement states are refused after a
  hit](cache-parts.md#results-computed-from-statement-states-are-refused-after-a-hit));
  the display of the final states (category `final-states`) asks for the
  outputs of a function through Eva's access to Inout
  (`Eva_dynamic.Inout.kf_outputs`), which answers `Top` after a hit without
  calling Inout;
- not restricted, and listed for issue #49: the values that `Eva.Results`
  returns at a statement of a function answered by a hit, which are top in
  the callstacks of the hits and over all callstacks
  ([Reach at a hit](reach.md#the-queries-see-the-points-reached-by-a-hit-with-the-state-top));
  and the readers built on them that report no status and no
  unreachability: the server requests of values (`getProbeInfo` reports a
  statement without a state as not evaluable), Studia, Dive, Aorai, the
  loop analysis, the callgraph and RTE (which reads the analysis status of
  a function);
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
call never divides by zero and never reaches `one`. The entry supplied by
hand without its Reach part (`PART=drop`) is rejected (`missing-points`),
and `body` is analysed: the statuses, the coverage of the summary (14
statements reached of 15) and the annotations that Export generates equal
those of caching disabled. After a change of the entry point, `body` is no
longer recorded among the functions whose visits a hit skipped. `supply`
refuses an entry for `outer`, which calls `body`; with this check removed
(a mutation, reverted), the entry of `outer` is supplied. In
`nested-access.t`, the produced entries of bodies with a call, and the hand
entry of a body that calls a specification, are rejected with
`nested-delivery`; at `cde85ebb5f`, before the check of `supply`, the hand
entries of bodies that call a function with a body were rejected so too.
The same runs with the produced entry, which has a Reach part, are the
evidence of
[The passes after the analysis read the points reached by hits](reach.md#the-passes-after-the-analysis-read-the-points-reached-by-hits).

`cache-reach.t`, `reach.c`, under `-eva-no-results-domain cvalue`: after
the hit, `body` is of unknown reachability, Export generates no annotation
in `body`, and `getDeadCode`, on the session saved after the analysis,
lists no statement of `body`; with caching disabled, Export generates
`\false` before the statements of lines 14 and 18, and `getDeadCode` lists
every statement of `body` as unreachable. The summary counts 14
statements reached of 14 in both runs. Each check fails with one change,
reverted after the run: with the test of `reach_unknown_of` removed from
`Export.generator`, Export generates `\false` before the statements of
lines 14 and 18 after the hit; removed from `dead_code`, `getDeadCode`
lists every statement of `body` as unreachable. With
`Safety_delivery.skip_visits` changed to record nothing, the fixtures
differ only in the record itself: no fixture shows its effect on the
statistics of a function. At `d9fbc62be5`, `mark_unreachable`,
`mark_green_and_red` and the coverage of the summary tested unknown
reachability, for a hit on an entry without a Reach part, which the lookup
now rejects. Runs of `reach.c` and `passes.c` under
`-eva-no-results-domain cvalue`, with caching enabled and disabled, with
Export, the refinement and the results installed again, made outside the
test suite, give the same output and the same response of `getDeadCode`
before and after the removal of these tests; `cache-reach.t` passes at
both revisions.

The warning of `Export.main` (option `-eva-annot`; the test calls
`Export.generator`) and the rejection when the Markdown report, WP or the
constant propagation is loaded rest on source inspection. The request
`getDeadCode` is executed in `cache-reach.t`, on the session saved after a
hit of `reach.c` under `-eva-no-results-domain cvalue`, also after the
results are taken and installed again, and the rejection when Nonterm or
Metrics is loaded is executed.

**What remains.** Issue #48 lifts the restriction: every hit delivers a
Reach part, and the lookup rejects an entry without one. It remains for
Export and `getDeadCode` after a hit whose points the queries do not see
(`-eva-no-results-domain cvalue`). An entry produced while the states of
the body were not saved has a Reach part without points: the lookup
rejects it where the states of the function are saved (`missing-points`),
and elsewhere no pass reads the points. The rejections of Nonterm,
Metrics, the Markdown report, WP and the constant propagation can be
lifted once the readers above are checked against the points reached by
hits. Once a stored body may call other functions (issues #50 and #51),
the entry must carry the functions whose visits its hit skips, so that a
hit records them all.

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
and `create` when there is no project. `load_projects` rebuilds the stack
after unmarshalling and puts back on top the project that was current
before, with no hook in between: the current project is unchanged. It then
calls `force_set_current`, which counts its change, removes that project
from the stack, and counts again: a hook run by `force_set_current` may
have made it current again, and the removal then changes the top. These are
all the
changes of the stack, which `project.ml` does not export: `Q.add_at_end` in
`create`, `Q.move_at_top` in `force_set_current`, `Q.remove` in `remove`
and in `load_projects`, `Q.clear` in `remove_all` and in `load_projects`,
and `Q.add` in `load_projects`. The kernel does not run the
hooks of the change of project for a change made during one of these
hooks, but it counts it. Each capture of the collector keeps the project and
the count at its start, and adds `Project_switch` to its refusals when the
count or the current project differs at its end. Every capture in progress
compares its own start, so the bodies whose analysis contains that of the
current one are refused as well. The producer stores no body with a refusal.
`Safety_part.record` compares the project and the count at the start of the
recording with the current ones at each write, and refuses instead of
recording when either differs. The count is a value of the process, not a
state of a project: it is neither saved nor loaded with a session. Since
every change of the current project increments the count, the comparison of
the count at the end of `Body_access.capture` decides the refusal; the
comparisons of the project, and the comparison at each write of the Safety
part, refuse no body that it does not refuse. The comparison at each write
serves the payload shown to the observers of `Safety_part.on_result`: the
writes it passes them, for a body refused or not, are all made in the
project of the recording. No test tells these comparisons apart from that
of the count. `Reach_part` makes the same comparisons at each write of the
Reach part, for the observers of `Reach_part.on_result`
([Reach at a hit](reach.md#the-reach-part-records-the-reach-of-the-body)).

**Evidence (executed).** `cache-safety.t`: a client of the statement hooks,
registered as classified so that the collector admits it, enters a second
project with `Project.on` the first time it runs in `body`, during the
analysis from `producer`, and sets a red status there. A client of the
hooks of red statuses, which an earlier version of the test used, now
refuses the body by itself (`callback`). The calls of `body`
and of `producer` read `collector: refused (project-switch)`, the statistic
`collector-refused-project-switch` is 1 for each, and no entry is produced.
The analysis from `main` then has no candidate, and its tables are those of
the run with caching disabled and the same client. With the comparisons of
the project and of the count removed from `Body_access.capture` and
`Safety_part.record` (a mutation, reverted), the entry is stored with the
red context set in the second project, and the hit delivers it in the
first: the tables of `main` have a red context of the reachability of the
statement at line 8 of `body`, which caching disabled does not have. With
the comparison of the count removed alone, `body` is still refused, by the
comparison of the project at its write in the second project, and
`producer` takes that refusal from the call of `body`: a recording takes
the refusals of the calls analysed within it (`Body_access.include_fresh`).

A change made in a hook of another change, in `cache-safety.t`: the
analysis from `producer` runs in a hook of the change of project to a copy
of the first project. The first time it runs in `body`, the client of the
statement hooks enters the first project with `Project.on` and leaves it,
without writing there.
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

The loading of two projects, in `cache-safety.t`: a hook of the change of
project makes current again, during the loading, the project that was
current before the last change. The loading then removes that project from
the top of the stack, and another one is current; the count differs from
the one that the hook saw. With the count at that removal taken out of
`load_projects` (a mutation, reverted), another project is current at the
same count. The test also prints the changes counted by some operations:
none for `set_current` of the current project and for `copy`, 2 for
`Project.on` left by an exception, 1 for `remove` of the current project,
and 5 for `load_all` of a session of two projects.

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
  the category `alarm` of Eva;
- the activation of every message category of Eva and of the kernel
  (`-eva-msg-key`, `-kernel-msg-key`), which decides whether a message is
  printed.

The lookup of a produced entry checks the second: it rejects the entry
(`warn-categories`) when the status of a category differs from its status
when the analysis of the body started. Within the analysis that uses an
entry, these settings change after the lookup only through a client of a
hook that the hit runs, and the lookup rejects every entry (`callback`)
while a client that is not audited is registered on such a hook. The
options, the activation of the message categories, and the categories of
an entry given to `Supplied_entries.supply` are owed by the supplier. A
violation can hide an alarm or a message, and with a category set to
abort, change the state at the end of the call.

**Kind.** OCaml obligation: the check of the lookup for the categories of
a produced entry, and the rejection of
[A hit runs no client that is not audited](#a-hit-runs-no-client-that-is-not-audited);
for the rest, owed by the supplier of an entry (`Supplied_entries.supply`
and `supply_produced`).

**Depends on.**
[A hit delivers the Safety part as recorded joins](#a-hit-delivers-the-safety-part-as-recorded-joins)
and [A hit runs no client that is not audited](#a-hit-runs-no-client-that-is-not-audited).

**Symbols.** `Body_access.warn_categories`, `Body_access.capture`,
`Cache_entry.dependencies`, `Supplied_entries.Lookup.find`,
`Supplied_entries.Lookup.admit`, `Supplied_entries.supply`,
`Supplied_entries.supply_produced`, `Kernel.SignedOverflow`,
`Evaluation.Make.handle_integer_overflow`, `set_warn_status`,
`get_all_warn_categories_status` and `logwith` in
[`log.ml`](../../../src/lib/utils/log.ml),
`Compute_functions.Make.compute_and_cache_call`.

**Argument (source inspection).** The Safety part records the writes of an
analysis of the body with the options of the producing analysis. An option
that turns a class of undefined behaviour into alarms changes these writes:
the same body emits an alarm under one setting and none under the other.
The delivery makes the recorded writes only, so an entry produced with
fewer alarms hides those that the analysis that uses it would emit.

The diagnostics of a body are of two kinds. The recorded messages, those
of the statuses and the reports of the alarms, all of the category `alarm`
of Eva, are printed again by a hit through the logger, at each occurrence:
the action of this category, and the activation of the message categories
that they use (`callstacks`, which adds the callstack to the text), are
those in force at the hit, as for an analysed call. The other diagnostics
of the body are not recorded and not printed by a hit; for instance, the
assumption of 2's complement for an overflow (category `signed-overflow`)
in a body analysed with the category inactive, or a message of a message
category such as `-eva-msg-key nonlin`. When the warning category of such
a diagnostic is set to abort at the hit, an analysis of the body stops at
the message, and the call has no state at its end, where the hit returns
the exit states of the entry. A message category decides only whether such
a diagnostic is printed: an activation that differs changes the printed
output, not the tables.

The status of a category can change between the producing call and the
hit: the two analyses are run with different settings; a hook changes a
category during the analysis, by `set_warn_status` or by setting
`-eva-warn-key`; or a later stage of the command line (`-then`) changes it.
`Body_access.capture` reads the status of every category of the kernel and
of Eva, but `alarm`, when the analysis of the body starts; the producer
stores it with the entry, and the lookup of the supplied entries reads it
again and compares. A change made before the lookup, by any of these means,
is seen. A change made during the analysis of a body is made by a client of
a hook, which refuses the body (`callback`): the status read at its start
is that of the whole body. A hit runs hooks after its lookup: the hooks on
calls; the hooks of the kernel on properties and statuses, the hooks of red
statuses and the listeners of the logger, when it prints the line of the
call and evaluates the preconditions; and the same hooks during the
delivery. The lookup rejects every candidate while a client that is not
audited is registered on one of them, and no audited client changes a
setting: no category changes between the lookup and the end of the
delivery. An earlier version compared the categories after the delivery,
and stopped the analysis when one had changed; it published the whole
Safety part first, where an analysis of the body stops at the message, and
missed a change undone before the comparison. The comparison was removed.
A `-once` category becomes inactive after its first message; the lookup
then rejects the entries produced before, which is conservative.

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
  the category inactive, and its entry is stored. At the end of the
  analysis of `other`, an observer of the Safety part supplies that entry
  and sets the category to abort; no hit runs such an observer
  ([A hit runs no client that is not audited](#a-hit-runs-no-client-that-is-not-audited)).
  The second call reads `lookup: rejected (entry 1: key-differs), rejected
  (entry 2: warn-categories)`, and stops at the overflow, as with caching
  disabled. With the comparison of `Supplied_entries.Lookup.admit` removed
  alone (a mutation, reverted), the second call hits and gives `out = 8`.
- `next.c`, the candidate after a rejection. The observer supplies the
  stored entry of `body`, then a copy written by hand, which carries no
  status of the categories. The second call reads `rejected (entry 1:
  key-differs), rejected (entry 2: warn-categories), hit (entry 3)`, and the
  tables are those of caching disabled.
- `overflow.c`, after the lookup. The entry is produced with the category
  inactive, and in the analysis that uses it, a client of the hooks on
  calls sets the category to abort at the call of `body`. The call reads
  `lookup: rejected (entry 1: callback); execution: interrupted`, the
  analysis stops at the overflow, as with caching disabled, and the tables
  are equal. With the flag of the hooks on calls removed from
  `Cvalue_callbacks` (a mutation, reverted), the hit prints nothing and
  gives `out = 8`, where caching disabled leaves `main` without a state.
  The other routes after the lookup, through the hooks on statuses, the
  hooks of red statuses and the listeners of the logger, are in
  [A hit runs no client that is not audited](#a-hit-runs-no-client-that-is-not-audited).

**Open.**

- The options and the activation of the message categories are not
  checked, and an entry given to `supply` carries no status of the
  categories. The entries saved with a session
  ([issue #59](https://github.com/nyandrianinamamy/frama-c/issues/59))
  cross analyses: they must store the options, the status of the warning
  categories and the activation of the message categories with the entry,
  and compare them at the lookup in the analysis that loads them.

## A hit runs no client that is not audited

**Claim.** A supplied entry is used at a call only when no client that is
not audited is registered on an interface that a hit runs between its
lookup and the end of its delivery, or that an analysis of the body runs
and a hit does not. Otherwise every candidate is rejected with `callback`,
before any candidate is examined and before any effect of the hit.
Registration is the test: a client registered after the production of an
entry counts. The client code that the lookup runs itself, the predicates
of the parts and of the readers of the statement states, runs before the
test, and no predicate runs between the test and the end of the delivery.
The audited clients are those listed below, and none of them tells a hit
from an analysis of the body in a way that changes the analysis. A client
that is not audited and runs during the analysis of a body refuses the body
(`callback`,
[ordered effects](collector-effects.md#ordered-and-opaque-effects)).

**Kind.** OCaml obligation, of Eva and of the kernel: each registration
function marked "test" in the table below records a client registered
without the flag of an audited one; the table and the list of audited
clients are those of the tree at this revision.

**Depends on.**
[Ordered and opaque effects](collector-effects.md#ordered-and-opaque-effects)
and
[A hit delivers the Safety part as recorded joins](#a-hit-delivers-the-safety-part-as-recorded-joins).

**Symbols.** `Supplied_entries.unaudited_clients`,
`Supplied_entries.Lookup.find`, `Cvalue_callbacks.unaudited_hooks`,
`Red_statuses.has_hooks`, `Property_status.has_add_or_update_hooks`,
`Annotations.has_unaudited_hooks_on_change`, `Log.unaudited_clients`,
`Messages.has_hooks`, `Cache_part.decide`, `Cache_part.unaudited_clients`,
`Safety_delivery.unaudited_subscribers`,
`Hook.Opaque.has_unaudited_observers`, `Base.has_unaudited_observers`,
`Origin.has_unaudited_observers`, `Async.has_daemons`,
`Current_loc.has_hooks_on_change`, `Eva_perf.has_hooks_on_change`,
`Safety_part.has_unaudited_observers`,
`Body_access.Result.has_unaudited_observers`,
`Safety_delivery.on_delivered`,
`Summary.FunctionStats.add_hook_on_change` (`audited`), `Kernel_ast` and
`States.install_hook` in the server, `Log.add_listener`,
`Log.on_history_access`, `register` in the signature `Log.Messages`,
`Compute_functions.Make.compute_and_cache_call`, `Safety_delivery.deliver`,
`Call_cache.report`.

**Argument (source inspection).**

*The path of a hit.* After the lookup, the hit branch of
`compute_and_cache_call` runs the call hooks of Eva (`` `Reuse ``),
completes the specification of the function (`Populate_spec`), evaluates
its preconditions, which emits statuses, red contexts and messages and
reads the validity of the allocated blocks that the preconditions name,
delivers the Safety part, which registers alarms, emits statuses, prints
messages and sets red contexts, delivers the Reach part, whose writes run
the hooks of change of tables internal to Eva, on which no client is
registered
([A hit delivers the Reach part as recorded joins](reach.md#a-hit-delivers-the-reach-part-as-recorded-joins)),
prints the line of the reuse and the disposition line of the category
`cache`, restores the parts of the entry in place of the call results
hooks, which only a hit of memexec runs, and updates the statistics of
the function in the summary (`Safety_delivery.delivered`). The hooks of
the kernel on annotations, properties, statuses and messages, and the
hooks of red statuses, run each client through `Hook.Opaque.wrap`, which
runs the observers of `Hook.Opaque` first. An analysis of the body runs
the same interfaces, and also, at each statement, the statement hooks of
Eva, a change of the current location and `Async.yield`, at each call
that it makes, the statistics of performance by callstack, and after the
body, the observers of the Safety part, of the Reach part and of the
results of the collector.

*The interfaces.* One row for each interface through which code registered
by a plug-in can run, found by the search described below. "Hit" says
whether a hit reaches the interface between the test and the return of
`Safety_delivery.delivered`; "Fresh" whether an analysis of the body
reaches it. The treatments are: "test", the lookup tests the interface,
with the flag of an audited client if any and the accessor that
`unaudited_clients` calls; "argued", neither a hit nor an analysis of the
body reaches it, for the reason given; "premise", the output premise of the
supplier (`supplied_entries.mli`), see the routes below; "outside", outside
the guarantee. The rows marked "new" were added by the sweep of this
revision; each had no treatment before.

| Interface | Hit | Fresh | Treatment |
| --- | --- | --- | --- |
| Call hooks of Eva (`Cvalue_callbacks.register_call_hook`) | yes, with `` `Reuse `` | yes | test, flag `cache_protocol` (`Cvalue_callbacks.unaudited_hooks`) |
| Call results hooks of Eva (`register_call_results_hook`) | no | yes | test, flag `cache_protocol` (same accessor) |
| Statement hooks of Eva (`register_statement_hook`) | no | yes | test, flag `classified` (same accessor) |
| Hooks of red statuses (`Red_statuses.register_hook`) | yes | yes | test, no flag (`Red_statuses.has_hooks`) |
| New property, new status (`Property_status.register_property_add_hook`, `register_status_update_hook`) | yes | yes | test, no flag (`Property_status.has_add_or_update_hooks`) |
| Changes of the annotations (`Annotations.add_hook_on_change`) | yes, at the registration of an alarm | yes | test, flag `audited` (`Annotations.has_unaudited_hooks_on_change`) |
| Logger: listeners (`Log.add_listener`), `register` of `Log.Messages`, observers of the history (`Log.on_history_access`) | yes | yes | test, flag `audited` (`Log.unaudited_clients`) |
| Message collector (`Messages.add_hook`) | yes | yes | test, no flag (`Messages.has_hooks`) |
| Parts (`Cache_part.register`), with the clients that their restoration runs (`Inout`'s `register_call_hook`) | yes, the restoration of the parts whose consumer is enabled | `provide` only | test, predicate `audited` (`Cache_part.unaudited_clients`) |
| Readers of the statement states (`Cache_part.register_state_reader`) | the predicate, before the test | no | `consumer`; the rules of the predicates (`cache_part.mli`) |
| Subscribers of the statistics by function (`Summary.FunctionStats.add_hook_on_change`) | yes | yes | test, flag `audited` (`Safety_delivery.unaudited_subscribers`) |
| Observers of the clients of the kernel hooks (`Hook.Opaque.on_call`) | yes, through each hook above that the kernel or Eva wraps | yes | new; test, flag `audited` (`Hook.Opaque.has_unaudited_observers`) |
| Reads of the metadata and updates of the validity of allocated blocks (`Base.observe_metadata_reads`, `Base.observe_validity_updates`) | yes for the reads, in the check of the preconditions; no update | yes | new; test, flag `audited` kept by the physical identity of the function (`Base.has_unaudited_observers`) |
| Accesses to the history of the origins (`Origin.on_history_access`) | when an evaluation of the preconditions creates an imprecise value | yes | new; test, flag `audited` (`Origin.has_unaudited_observers`) |
| Daemons (`Async.on_progress`, `while_progress`, `with_progress`) | no: a hit does not call `Async.yield` | yes, at each statement | new; test, no flag (`Async.has_daemons`) |
| Current location (`Current_loc.add_hook_on_change`) | no: Eva changes it in the iterator, the initialization and the passes after the analysis | yes, at each statement | new; test, no flag (`Current_loc.has_hooks_on_change`) |
| Statistics of performance by callstack (`Eva.Eva_perf.StatByCallstack.add_hook_on_change`) | no; the start and end of the call run outside this interval, with another duration | yes, at each call that the body makes | new; test, no flag (`Eva_perf.has_hooks_on_change`) |
| Observers of the Safety part (`Eva.Safety_part.on_result`) | no | yes | new; test, flag `audited` (`Safety_part.has_unaudited_observers`) |
| Observers of the results of the collector (`Eva.Body_access.on_result`) | no | yes, with `-eva-cache-collect` | new; test, flag `audited` (`Body_access.Result.has_unaudited_observers`) |
| Generation modes of specifications (`Populate_spec.register`) | no | no | argued: `populate_funspec` without `do_body` generates nothing for a function that has a body |
| Builtins (`Eva.Builtins.register_builtin`) | no | at a call that the body makes | argued: the producer refuses such a body (`builtin`); the supplier owes it for an entry given to `supply` |
| Domains (`Eva.Domain.register`) | no | no | argued: a registered domain runs only when it is enabled, and an enabled domain other than cvalue rejects every candidate with `product`; the hooks that transform the abstractions (`Abstractions.Hooks.register`, `Engine.register_hook`) are internal to Eva (outside), and those of the tree return the abstractions unchanged unless their own domain or value is enabled |
| Analysis hooks (`Cvalue_callbacks.register_at_start_hook`, `Analysis.register_computation_hook`) | no | no | argued: they run at the start, the end or the reset of an analysis; a reset during an analysis rejects with `analysis-reset` |
| Compute hooks of the statistics (`Eva.Statistics.add_compute_hook`) | no | no | argued: they run when the statistics are exported; `Statistics.incr` writes in tables that Eva does not export |
| Hooks on the options (`add_set_hook`, `add_update_hook` of a parameter) | no | no | argued: neither sets an option; the analysis of threads, which does, rejects with `consumer` |
| AST and projects (`Ast.add_hook_on_update`, `Ast.apply_after_computed`, the hooks of `Cabs2cil` and `Frontc`, `Project.register_create_hook` and the other hooks of `Project`) | no | no | argued: no AST is built or changed and no project operation runs; a change of the current project refuses the recordings |
| Removals (`Property_status.register_property_remove_hook`, the removal hooks of `Emitter.Make_table`) | no | no | argued: nothing is removed during a call |
| Stages of the command line (`Cmdline.run_after_*`, `Boot.Main`), `Task.on_idle` | no | no | argued: outside an analysis |
| Dynamic registrations (`Dynamic.register`, read by `Eva_dynamic` with `Dynamic.get`) | no | no | argued: Eva reads Scope, Callgraph and the outputs of Inout after the analysis, and registers its client of Inout once, as audited |
| State hooks of Callgraph (`StateHook` of `Cg` and `Services`) | no | no | argued: the call graph is not computed during a call |
| State hooks of the other exported states of the kernel (`Logic_env`, `Ast_diff`, `Parameter_state.Is_set`, `Cil_builtins`) | no | no | argued: none is written during a call |
| Printers: `Printer.update_printer`, the printing references of `Cil` and `Cil_datatype`, the printers of `Acsl_extension`; the formatter (`Log.set_formatter`), the history test (`Log.check_not_yet`) and the output sinks of the logger | yes | yes, other lines | premise |
| Forward references of the kernel (`ref` values of an interface, set by other kernel modules: `Log.set_current_loc`, those of `Globals`, `Cil_datatype` and `Parameter_builder`) | yes | yes | outside: a replacement replaces part of the kernel |
| Internal modules of Eva (`Eva__Private`, the other `Eva__*` units: the tables of red contexts and of skipped visits, the computation state, `Safety_delivery.on_delivered`) | yes | yes | outside; `on_delivered` is one-shot |

*How the search was done.* The table was built from the hit path traced in
the source, from the test in `Supplied_entries.Lookup.find` to the return of
`Safety_delivery.delivered`, and from searches of the tree by mechanism,
excluding the tests. A reviewer can repeat them:

```sh
git grep -nE 'Hook\.(Build|Make|Fold|Build_ordered|Make_ordered|Fold_ordered)\b|Hook\.Opaque' -- 'src/*.ml' 'plugins/*.ml' ':!*/tests/*'
git grep -nE 'add_hook_on_change|add_hook_on_update' -- 'src/*.ml' 'plugins/*.ml' ':!*/tests/*'
git grep -nE ':.*->.*\) ref\b|: *\(.*->.*\) option ref' -- 'src/*.mli' 'plugins/*.mli'
git grep -nE 'State_builder\.(Ref|Hashtbl|Option_ref|List_ref|Counter|Proxy|Set_ref)' -- 'src/*.mli' 'plugins/*.mli'
git grep -nE 'Async\.(yield|on_progress|while_progress|with_progress)' -- 'src/*.ml' 'plugins/*.ml'
git grep -nE 'observe|on_call|add_listener|register_.*hook|extend\b' -- 'src/*.mli' 'plugins/*.mli'
git grep -nE 'Dynamic\.(get|register)|Eva_dynamic\.' -- 'src/*.ml' 'plugins/*.ml'
git grep -nE '(Parameters|Kernel)\.[A-Za-z_]+\.(set|on|off|add)\b' -- plugins/eva/src
git grep -nE 'Current_loc\.(set|with_loc)|UpdatedCurrentLoc' -- 'src/*.ml' 'plugins/*.ml'
```

with the list of the modules that `Eva.ml` exports. Each hit of these
searches was classified by whether it is exported and whether code on the
hit path or on the path of an analysis of the body calls it. Instances that
are not exported (the hook of From on its callwise results, the hooks of
`Statistics` other than `add_compute_hook`, the tables of `Mt_summary` and
of `Self`) are not rows. Functions run when a process exits are excluded.

*The test.* Each registration function marked "test" records whether it
registered a client without the flag of an audited client (`cache_protocol`
or `classified` for the hooks of Eva, `audited` for the others that have
one, the predicate `audited` for the parts); for the others, any
registration counts. A client cannot be removed, apart from a daemon of
`Async`, which counts while it is registered; an observer of `Base` removed
since counts. `unaudited_clients` is the disjunction of the sixteen
accessors, and `find` tests it after `product`, `consumer` and
`stop-at-nth-alarm` and before it examines the candidates: no hook has run,
nothing has been delivered and no line has been printed for the hit when
the candidates are rejected.

*The client code of the lookup.* `Cache_part.decide`, which a lookup with
candidates calls once, after `product` and before `consumer`, takes the
answers of the predicates in two passes: first those of the readers of the
statement states (`Cache_part.register_state_reader`) and `needed` for
every part, then `audited` for the parts whose consumer is enabled. The
test of `consumer`, the test of the parts in `unaudited_clients`, the check
of the parts of each candidate (`missing-part`) and the restoration at the
hit use these answers, and a part registered since they were taken counts
as not audited. A client that a predicate of the first pass registers on
an interface tested above, or on a hook whose clients a part audits, is
seen by the audits and by the test of the same lookup. A function
`audited` that registers a client is outside the contract of
`cache_part.mli`: the audits asked before it do not see the client.
`cache_part.mli` states what a predicate may do: return a result, register
nothing and write in no table. Before the two passes (at `3f54601636`), a
predicate `needed` or of a reader of the statement states that registered
a client of Inout after the audit of the part of Inout let the first call
hit, and the client ran at its restoration.

*From the test to the end of the delivery.* The client code that runs
between the test and the end of `Safety_delivery.delivered` is covered as
follows.
- The restore functions of the parts run only for the parts whose answers
  say that their consumer is enabled and that they are audited: they
  belong to audited registrations. `Cache_part.provide` runs in the
  analysis of a body, never at a hit. The parts have no printer, and the
  reasons of rejection and refusal are printed by Eva's own functions. The
  check that the function of an entry belongs to the current project runs
  when the entry is supplied, not at the lookup.
- Every other interface reached is a row of the table with the treatment
  "test", "premise" or "outside".

*The audited clients of the tree.*
- The observers of the collector of block accesses (`Body_access`): of
  `Hook.Opaque`, of the reads of the metadata and the updates of the
  validity of allocated blocks, of the history of the origins and of the
  history of the logger, each registered with `audited`. They are part of
  the collector: outside a recording they refuse nothing and write only in
  the counters of the collector (`Body_access.history_consultations`), and
  the observers of `Base`, installed while a body is recorded, run the
  observer that they replaced. The observer of `Hook.Opaque` runs at a hit
  through the client of the server on the annotations (below), and refuses
  the body being recorded around the hit, if any; the observer of the
  metadata runs at a hit through the check of the preconditions, and
  records the read in the body being recorded, if any.
- The message collector of the kernel (`Messages`, a listener registered
  with `audited`) appends each message to the table of messages. A hit
  appends its own lines and the messages of its Safety part, where an
  analysis of the body appends the diagnostics of the body: the table
  differs as the printed output does. It is read by the hooks of the
  collector, which are checked, and after the analysis, by the server and
  the graphical interface.
- The error flag of the parser (`Errorloc.set_error`, registered with
  `register` and `audited`) is set by an event of kind error or failure
  on the channel of the kernel. A hit emits on the channel of Eva only:
  its dispositions and the messages of its Safety part. It therefore does
  not run this listener, and a fresh analysis of the body runs it only if
  the body makes the kernel emit an error or a failure, which no
  regression does (open: such a body is neither refused nor recorded for
  that reason). The flag is not cleared by every reader: `Frontc` and
  `Mergecil` clear it before the phase whose errors they test, and
  `File.to_cil_cabs` reads it after an external parser without clearing
  it, so a flag set earlier reaches that reader (shown with the `.cc`
  test parser: an empty file is accepted, and rejected after a kernel
  error event). The argument for this client is that a hit does not set
  the flag, not that the flag is local to a phase.
- The call and call results hooks registered with `cache_protocol`: those
  of Inout and From (callwise), whose call hooks do nothing with
  `` `Reuse `` and whose results hooks a hit of a supplied entry does not
  run; that of the analysis of threads, whose activity rejects every
  candidate with `consumer` first; and that of the summary
  (`Summary.FunctionStats`), which computes the statistics of a function at
  its `` `Body `` results. After a hit that skipped its visits, the engine
  calls `Safety_delivery.delivered`, through which the summary computes them
  again from the tables that the delivery has updated. The summary installs
  this function once, when Eva is loaded (`Safety_delivery.on_delivered`);
  another installation raises `Invalid_argument`. Both updates run the
  subscribers of the statistics: none of the tree is audited (below). A
  subscriber sees one update of a function after each analysis of its body
  and one after each hit on it, then one for each function at the end of
  the analysis. After a hit, `Eva.Results.statement_results_complete` is
  false, and the statistics count the statements of a function answered by
  a hit as reached, as an upper bound; during the analysis, the results
  answer that every statement is reachable, with or without hits. On
  `parts.c`, the statistics of `copy` are the same at each update of the
  two analyses, and only the completeness of the results differs. A
  subscriber registered as audited owes that its effects do not depend on
  this difference (`summary.mli`).
- The parts of From and Inout (`Cache_part.register` with `audited`), and
  Eva's client of the hook of Inout on the inputs and outputs of each call
  (`Transfer_stmt.InOutCallback`, registered through
  `register_audited_call_hook`): the restoration writes what the analysis
  of the body writes once its result is computed, in tables that From and
  Inout do not export, and gives Eva the result of the call before the
  caller reduces its actuals. Argued in [The restoration of a part runs
  audited clients
  only](cache-parts.md#the-restoration-of-a-part-runs-audited-clients-only).
- The client of the server on the changes of annotations (`Kernel_ast`,
  registered with `audited`), loaded with the server, which Callgraph
  links, and From and Inout link Callgraph. It emits the signal `changed`
  of the server (`Main.emit`). With no server running, the emitter is
  `nop`; with a server running, `Main.do_signal` adds the signal to the
  sets of the server and to its queue of messages, and runs no hook
  (`notify` runs only when the client of the server starts or stops
  listening). No analysis reads these. What the client of the server does
  when it receives the signal, between two steps of the analysis, is
  outside this claim, as the output sinks of the logger are. The audit is
  for the lookup only: the invocation still reports to `Hook.Opaque`, and
  the collector refuses a body during which it runs
  ([ordered effects](collector-effects.md#ordered-and-opaque-effects)). At
  a hit that registers an alarm, it runs the observers of `Hook.Opaque`,
  which the lookup admits only when all are audited.
  Its premise is a server that is linked and not started, the
  configuration in which the hits of `cache-parts.t` with the server
  loaded are executed. A review replayed `parts.c` with a
  server started and a client connected: no call hit, and the nine
  candidates of `copy` read `callback`, since the server installs a
  listener of the logger when it starts, which is not audited. The timing
  and the number of the signals under a configuration of the server that
  admits a hit are not established; no such configuration exists in the
  tree at this revision.
- The statement hooks registered as classified: the watchpoints
  (`Builtins_watchpoint`), whose activity rejects every candidate with
  `watchpoint`, and the dynamic widening hints (`Widen`), whose change
  rejects an entry with `hint-generation`. A hit runs no statement hook.

The other clients of the tree are not audited, and reject every candidate
once registered: the server registers hooks on statuses, red statuses and
messages when a client of its protocol listens, and subscribes to the
statistics by function of the summary and to the statistics of performance
by callstack when a client listens to the signal of the array
`functionStats` or `flamegraph` (`States.install_hook` registers the
subscription at the `SigOn` of the signal). With no server running, or no
client listening, these subscriptions are not registered; with a server
running, its listener of the logger already rejects every candidate, and so
does its daemon of `Async` (`Main.start`, and `Async.with_progress` around
each request that it executes). They therefore change no hit at this
revision. The Report plug-in, the logging of a plug-in to a file
(`-<plug-in>-log`) and the monitoring of the server register a listener;
the inlining of statement contracts registers hooks on statuses.

*Routes that the test does not close.* A client outside the tree
registered with the flag of an audited client is trusted; for an observer
of `Base`, the flag is kept with the function, and a function installed
once with the flag is trusted when it is installed again without it. The
rows "premise" of the table are replaceable parts that are not
registrations and that the test does not see: the formatter installed with
`Log.set_formatter`, the history test `Log.check_not_yet`, the output sinks
of the logger, and the printers that a plug-in replaces or extends
(`Printer.update_printer`, the printing references of `Cil` and
`Cil_datatype`, the printers of `Acsl_extension`), which format the
elements of the AST named in the messages, at a hit as in an analysis of
the body, in other lines. A replacement that acts on what it prints or
tests can tell a hit from a fresh call without declaring itself audited:
with a formatter that sets `alarm` to `abort` when it sees the disposition
of a hit, the delivery stops at the first status message where the run
with caching disabled completes with `r1 = 9` and `r2 = 8`. No plug-in of
the tree installs such a replacement. The guarantee of this entry is for
the logger and the printers of the tree with output sinks that do not act
on the analysis; the supplier owes it (`supplied_entries.mli`). The rows
"outside" are not part of the interface of the kernel or of Eva: the
forward references of the kernel, and the internal modules of Eva
(`Eva__Private` and the other `Eva__*` units, which the build exposes),
including the hooks of the internal tables that a hit changes
(`State_builder` hooks of the table of red contexts, of the functions with
skipped visits). A module that reaches them can call or replace what the
engine relies on. The installation of the update of the summary is
one-shot, so that such a module cannot replace it silently: a second
installation raises. The observers of the collector and of the Safety part
registered as audited are test devices of the cache, through which a test
reads the dispositions; no plug-in of the tree registers one, and `same.c`
uses one, registered as audited, to change a setting between two calls,
which the audit of a test device does not cover.
The observers of the Reach part (`Reach_part.on_result`) run after the
analysis of a body and never at a hit; no plug-in of the tree registers
one. The hooks of the tables that the delivery of the Reach part writes
are not part of the interface of Eva: their modules are not in the
interfaces of their compilation units, and no client is registered on
them
([A hit delivers the Reach part as recorded joins](reach.md#a-hit-delivers-the-reach-part-as-recorded-joins)).

**Evidence (executed).** `cache-safety.t`, each scenario compared with the
run with caching disabled and the same clients, on the tables of statuses,
alarms and red contexts and on the state at the end of `main`:

- One client of each hook, registered after the analysis from `producer`
  of `safety.c` (call, call results, statement, red statuses, statuses,
  properties, annotations, `Log.add_listener`, `Kernel.register`,
  history, messages): both calls of `body` reject the entry with
  `callback`. With only the audited clients registered, the call at line
  26 is a hit. With the server plug-in loaded, its client of the hooks on
  annotations runs when `body` registers its alarm: the body is refused
  (`callback`), no entry is stored, and the analysis from `main` has no
  candidate. In `cache-parts.t`, with the server loaded and the bodies
  registering no alarm, the three calls to `copy` hit; before the audit of
  this client, every candidate of the file read `callback`, the server
  being loaded with From and Inout.
- `inside.c`: a client of the hooks on calls sets `signed-overflow` to
  abort at the call of `body`, and a client of the hooks of red statuses
  sets it back at each red status. Both calls reject the entries with
  `callback`, and the analysis stops at the overflow, as with caching
  disabled. When red clients were admitted, the red status restored the
  category before the comparison after the delivery, and the hit gave
  `out = 8`.
- `interleave.c`: a client of the hooks of red statuses counts its calls;
  the call is rejected, and the client is called once before the analysis
  stops, as with caching disabled; the hit called it three times and set
  the red status of `last` before the comparison stopped the analysis.
- `pre-route.c`: a client of the hooks on statuses sets `signed-overflow`
  to abort when the precondition of `pre` is evaluated. The entry is
  rejected and the analysis ends with `out = 5`, as with caching disabled;
  the comparison after the delivery stopped the hit.
- `later.c`: a listener of the logger sets the category when it reads the
  line of a hit on `body`. The entry is rejected and the analysis ends
  with `out = 8`, as with caching disabled; the comparison stopped the hit.
- `repeat.c`: a client of the hooks of red statuses adds a red status of
  its own. Registered after the production, it rejects the entry, and the
  hook is called 6 times, as with caching disabled, where the hit called it
  12 times. Registered before the production, it refuses the body
  (`callback`), no entry is stored, and the tables are those of caching
  disabled; the hit set a global red context of `never` that the analysis
  from `main` does not set.
- `second.c`: a client of the hooks of red statuses sets `alarm` to abort
  at its second call. Both calls reject the entries, and the analysis stops
  at the second message of `later`, as with caching disabled; when the
  Safety part kept one message per text, the hit gave `out = 8`.
- The rows "new" of the table: one client of each, registered after the
  analysis from `producer` of `safety.c` (`opaque`, `metadata`, `validity`,
  `origin`, `daemon`, `location`, `perf`, `safety-result`,
  `collector-result`), makes both calls of `body` reject the entry with
  `callback`.
- `alone.c` (`safety.c` without the first call of `body`), with the server
  loaded after the analysis from `producer`: the hit on `body` registers an
  alarm, which runs the client of the server on the annotations through
  `Hook.Opaque.wrap`. An observer of `Hook.Opaque` registered without an
  audit makes the call reject the entry (`hits on body: 0, rejected for
  callback: 1`) and is not called during a delivery; registered as
  audited, the call hits and the observer is called once during the
  delivery. Before the test of `Hook.Opaque` (at `3f54601636`), a review
  observed the observer without an audit running at the hit after the
  visits were skipped. On `alone.c`, the status of the alarm at the end
  differs from the run with caching disabled (unknown against invalid):
  the passes after the analysis draw no conclusion in a function whose
  visits a hit skipped, as stated in the entry on these passes.
- `metadata.c`, with `-eva-alloc-returns-null`: the precondition of `pre`
  reads the validity of an allocated block, and a hand-written entry
  answers the second call. An observer of the reads of the metadata
  registered without an audit makes both calls reject the entry (`hits on
  pre: 0, rejected for callback: 2`) and is not called during a delivery;
  registered as audited, the second call hits and the observer is called
  once during the check of its preconditions, through the observer of the
  collector that records `main`. Before the test of `Base` (at
  `3f54601636`), a review observed the observer without an audit running
  in the admitted hit, before the visits were skipped.

In `cache-parts.t`:

- Scenario `predicate`: a part never needed and not audited, whose
  predicate registers a call hook of Eva at its first or at its second
  evaluation in the analysis with the supplied entries. At the first, the
  three calls to `copy` read `callback` for their three candidates; at the
  second, the first call hits and the two others read `callback`. The hook
  receives no call with `` `Reuse ``, and the predicate runs 7 times, once
  for each lookup with candidates. At `2bfc8508ce`, before the answers were
  taken once, both gave `hits 1`, one call with `` `Reuse `` and 3
  evaluations.
- Scenario `predicate` with `EVA_TEST_CACHE_PARTS_CLIENT=inout`: the
  predicate `needed` of a part registered after the parts of From and
  Inout registers a client of the hook of Inout on its first evaluation.
  The three calls to `copy` read `callback` for their three candidates,
  and the client is called 0 times after a hit on `copy`. With
  `EVA_TEST_CACHE_PARTS_CARRIER=reader`, the predicate of a reader of the
  statement states registers it, with the same results. At `3f54601636`,
  when the audit of the part of Inout ran before these predicates, both
  gave `copy: hits 1, rejected for callback 6`, and the client was called
  10 times after the hit.
- Scenario `predicate` with `EVA_TEST_CACHE_PARTS_CLIENT=part`: the
  predicate registers a part at its first evaluation. The first call to
  `copy` rejects its three candidates with `callback`, and the next two
  hit (`copy: hits 2, rejected for callback 3`): the part registered since
  the decisions counts as not audited in the lookup that registered it,
  and has no consumer in the next ones.
- Scenario `stats`: a subscriber of the statistics by function registered
  without an audit gives `copy: hits 0, rejected for callback 9`; registered
  as audited, the three calls hit, and its four updates of `copy` read
  `complete false, reached 2` where those of the analysis with caching
  disabled read `complete true, reached 2`. At `2bfc8508ce`, the subscriber
  without an audit let the three calls hit.
- Scenario `replace-summary`: a second installation through
  `Eva__Private.Safety_delivery.on_delivered` is refused, and the three
  calls to `copy` hit. At `2bfc8508ce`, a module outside the tree replaced
  it, and its function ran at the seven hits of `parts.c`.
- The scenarios with the server loaded and not started keep their hits
  (`copy 3`): the server registers no subscription to the statistics.

Mutations, each run alone and reverted. With the rejection removed from
`find`, every client of the first scenario lets the call at line 26 hit;
`overflow.c` after the lookup hits and gives `out = 8`, where caching
disabled leaves `main` without a state; `interleave.c` hits and calls the
client of red statuses three times, against once. With one of the six
accessors of #47 removed from `unaudited_clients`, the line of its clients
in the first scenario reads `hits on body: 1`, and the scenario on its route
hits: `overflow.c` after the lookup for the hooks of Eva, with `out = 8`;
`repeat.c` with the client registered after the production for the hooks
of red statuses; `pre-route.c` for the hooks on statuses; `later.c` for
the logger. With the seventh, `Cache_part.unaudited_clients`, removed, the
scenarios `unaudited-part` and `inout-client` of `cache-parts.t` give
`copy: hits 3, rejected for callback 0` where they give `hits 0, rejected
for callback 9`. With the eighth, `Safety_delivery.unaudited_subscribers`,
removed, the subscriber of the scenario `stats` registered without an audit
lets the three calls hit. With the check of the parts evaluating the
predicate again instead of using the answers of the lookup, the scenario
`predicate` with the hook registered at the second evaluation gives one
call with `` `Reuse `` and 8 evaluations. With the installation of the
update of the summary no longer one-shot, the scenario `replace-summary`
installs a second function, which runs at the seven hits. Each flag of
the hooks of Eva (call, call results, statement)
and of the logger (`add_listener`, `register`, `on_history_access`), and
each half of `has_add_or_update_hooks`, removed alone, makes the line of
its own client hit. With the hooks of red statuses no longer opaque, the
body with the client of `repeat.c` registered before the production is
stored, and the red client of `collector-effects.t` reads `would-store`.
`inside.c`, `interleave.c`, `second.c`, `pre-route.c` and `later.c` are
the programs of a review of the previous version, where red clients were
admitted and the categories were compared after the delivery; that review
observed the results quoted above for that version.

With one of the eight accessors of the rows "new" removed from
`unaudited_clients`, the line of its client in the first scenario reads
`hits on body: 1, rejected for callback: 0`; without the accessor of
`Hook.Opaque`, the observer without an audit on `alone.c` lets the call hit
and is called once during the delivery, and without that of `Base`, the
observer without an audit on `metadata.c` lets the second call hit and is
called once. With the observer of `Hook.Opaque` or of the metadata of the
collector registered without `audited`, the audited observer of `alone.c`
or of `metadata.c` no longer lets its call hit (`hits on body: 0`, `hits on
pre: 0`). With `decide` evaluating `audited` right after `needed` for each
part, in one pass, the scenario `predicate` with the client of Inout gives
`copy: hits 1, rejected for callback 6` and 10 calls of the client; with
the predicates of the readers evaluated after the audits, the same scenario
with `EVA_TEST_CACHE_PARTS_CARRIER=reader` gives the same. With the count of
the parts registered since the decisions compared with itself in
`Cache_part.unaudited_clients` (the field kept used, as warning 69 requires),
the scenario with a registered part gives `copy: hits 3, rejected for
callback 0`. Each mutation was applied alone to `b37d163154` and reverted.

Of the hit scenarios of `cache-safety.t` before this rule, one now
rejects: `overflow.c` with the client of the hooks on calls. Three tests
that counted the calls of a client of the hooks of red statuses at a hit
(`loop.c`, `abort-count.c`, `repeat.c`) now run without it: with it, they
reject. The hit scenarios of `collector-effects.t` and of the `cache_supplied`
tests register no client and are unchanged.

**Open.**

- The table and the list of audited clients come from a sweep of the tree
  at this revision; a new interface that a hit or an analysis of the body
  runs must get a row, and an accessor here unless it is argued.
- The rejection costs every hit while a client is registered, for instance
  with the log of a plug-in written to a file, while a client of the
  protocol of the server listens to statuses, or while a server runs: its
  daemon of `Async` and its listener of the logger are not audited.
- The row of the accesses to the history of the origins at a hit is from
  source inspection; no regression makes the check of the preconditions of
  a hit create an imprecise value.
- With the server loaded, which From and Inout load, the collector refuses
  every body that registers an alarm: its client of the hooks on the
  changes of annotations is audited at the lookup only.
- The printers of the kernel that a plug-in replaces or extends are not
  tested; a hit and an analysis of the body print other lines with them.
- The subscriptions of the server to the statistics by function and to
  the statistics of performance by callstack are not audited. They change
  no hit at this revision; a configuration of the server that admits hits
  would reject every candidate while a client listens to the array
  `functionStats` or `flamegraph`.

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
