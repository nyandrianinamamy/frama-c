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
frames). An alarm also keeps its predicate: the one of its annotation if the
alarm is already registered, or else the one that the kernel builds for it
when the body emits it. The checks of the `requires` clauses of the called
function belong to the call site and are not recorded. The producer stores these
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
  an evaluation, takes the predicate of the alarm (`Alarms.predicate`),
  records the write with it, and calls `Alarms.register` with the status
  and this predicate;
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
of the Safety part, and no hit delivers or computes them: under that
option the lookup rejects every candidate
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
the call as frame; a hit checks no precondition
([Preconditions at a hit](#preconditions-at-a-hit)). It holds none of the
writes made in the bodies analysed
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

**Claim.** At a hit on a supplied entry, the writes of the Safety
part are made again, in their order, each for the callstack of the hit
extended by its frames. Each write goes through the function that the body
uses, so that the kernel or Eva joins it with the value already at its
position. An alarm is registered with the predicate that its write holds:
the delivery builds no predicate, no term and no cast. No hit is on a
function whose call checks a `requires` clause
([Preconditions at a hit](#preconditions-at-a-hit)). This is an instance of
the `RecordedWrite` contract of
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
status of that emitter on the annotation. It makes the annotation from the
predicate that it receives (`?predicate`): the one of the write at a hit,
the one that `Alarms.predicate` gave to `Alarmset.register` in an analysis
of the body. `Alarms.predicate` returns the predicate of the annotation of
an alarm already registered, and otherwise builds one
(`Alarms.create_predicate`), with casts (`Cil.mkCast`) and, for the alarms
on floats, a built-in predicate that `Logic_env.find_all_logic_functions`
adds to the table of logic functions at its first use. A hit calls neither:
`Safety_delivery.deliver_write` passes the predicate of the write to
`Alarmset.deliver`, and `Alarms.to_annot_aux` builds one only when it
receives none. The existence of the annotation is
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
(`Cvalue_domain.State.Store.is_computed`). Under
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
  (states before a statement as hypotheses of its memory model based on Eva),
  the constant propagation (values at statements) and Occurrence (accesses
  dropped when their address is not precise); loaded after a hit, each is
  refused the states at the statements by the results of Eva
  ([Results computed from statement states are refused after a
  hit](cache-parts.md#results-computed-from-statement-states-are-refused-after-a-hit),
  which lists every reader of the tree with its class);
- the results by function of From and Inout, computed from the states
  saved at statements, and their readers: From, Inout, Pdg and the
  requests `getReadsLval` and `getWritesLval` of Studia refuse them after
  a hit, and every supplied candidate is rejected as `consumer` while
  Pdg, Reduc (assertions from the values at statements, given a valid
  status) or Studia, or a plug-in that loads one of them, is loaded
  ([Results computed from statement states are refused after a
  hit](cache-parts.md#results-computed-from-statement-states-are-refused-after-a-hit));
  the display of the final states (category `final-states`) asks for the
  outputs of a function through Eva's access to Inout
  (`Eva_dynamic.Inout.kf_outputs`), which answers `Top` after a hit without
  calling Inout, and prints, for a function with a call answered by a hit,
  the number of these calls in place of its values
  ([A function with a call answered by a hit has no final
  values](cache-parts.md#a-function-with-a-call-answered-by-a-hit-has-no-final-values));
- not restricted, and listed for issue #49: the values that `Eva.Results`
  returns at a statement of a function answered by a hit, which are top in
  the callstacks of the hits and over all callstacks
  ([Reach at a hit](reach.md#the-queries-see-the-points-reached-by-a-hit-with-the-state-top));
  and the readers built on them that report no status and no
  unreachability: the server requests of values (`getProbeInfo` reports a
  statement without a state as not evaluable) and the loop analysis.
  Aorai, the callgraph and RTE read no state saved at a statement. While
  a plug-in listed as a reader is loaded, these queries are refused after
  a hit, for every reader of the process: Dive, which loads Studia, is
  refused;
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
`Safety_delivery.skip_visits` changed to record nothing (applied to
`4f20abfe60` and reverted), the fixtures of `cache-reach.t` differ only in
the record itself, and no fixture shows its effect on the statistics of a
function; the readers that test the record are those of
[Results computed from statement states are refused after a hit](cache-parts.md#results-computed-from-statement-states-are-refused-after-a-hit),
whose refusals in `cache-parts.t` all disappear under this change. In
`cache-safety.t`, the record and the count of the observer calls during a
delivery on `alone.c` change: the test module detects a delivery through
this record. At
`d9fbc62be5`, `mark_unreachable`, `mark_green_and_red` and the coverage of the
summary tested unknown reachability, for a hit on an entry without a Reach
part, which the lookup now rejects. Runs of `reach.c` and `passes.c` under
`-eva-no-results-domain cvalue`, with caching enabled and disabled, with
Export, the refinement and the results installed again, made outside the
test suite, give the same output and the same response of `getDeadCode`
before and after the removal of these tests; `cache-reach.t` passes at
both revisions.

The warning of `Export.main` (option `-eva-annot`; the test calls
`Export.generator`) rests on source inspection. The rejection when the
Markdown report, WP or the constant propagation is loaded is executed in
`cache-parts.t`. The request
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
call; and the same hooks during the
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

The claim rests on a reading of the code that a hit runs, not on the list
of the clients found so far. From the test to the end of its delivery, a
hit runs the calls listed under *What a hit runs*, and no other. It
evaluates no term and no predicate, builds none, and visits no part of the
AST. Each call of the list was read down to functions that call no function
held in a mutable place; each call of such a function met on the way has a
row in the table of interfaces, with the test of the lookup, the premise or
the exclusion that covers it. What the reading does not cover is listed
under *Outside the guarantee*.

**Kind.** OCaml obligation, of Eva and of the kernel: each registration
function marked "test" in the table below records a client registered
without the flag of an audited one; the list of calls, the table and the
list of audited clients are those of the tree at this revision.

**Depends on.**
[Ordered and opaque effects](collector-effects.md#ordered-and-opaque-effects),
[A hit delivers the Safety part as recorded joins](#a-hit-delivers-the-safety-part-as-recorded-joins)
and [Preconditions at a hit](#preconditions-at-a-hit).

**Symbols.** `Supplied_entries.unaudited_clients`,
`Supplied_entries.unaudited_status_dependents`,
`Supplied_entries.Lookup.find`, `Supplied_entries.Lookup.admit`,
`Cvalue_callbacks.unaudited_hooks`,
`Red_statuses.has_hooks`, `Property_status.has_add_or_update_hooks`,
`Annotations.has_unaudited_hooks_on_change`,
`Project.has_unaudited_clear_hooks`, `State.has_hooks_on_update`,
`Cil.has_inserted_cast_hook`, `Logic_env.has_hooks_on_logic_functions`,
`Log.unaudited_clients`,
`Messages.has_hooks`, `Cache_part.decide`, `Cache_part.unaudited_clients`,
`Safety_delivery.unaudited_subscribers`,
`Hook.Opaque.has_unaudited_observers`, `Base.has_unaudited_observers`,
`Origin.has_unaudited_observers`, `Async.has_daemons`,
`Current_loc.has_hooks_on_change`, `Eva_perf.has_hooks_on_change`,
`Safety_part.has_unaudited_observers`,
`Reach_part.has_unaudited_observers`,
`Body_access.Result.has_unaudited_observers`,
`Safety_delivery.on_delivered`,
`Summary.FunctionStats.add_hook_on_change` (`audited`), `Kernel_ast` and
`States.install_hook` in the server, `Log.add_listener`,
`Log.on_history_access`, `register` in the signature `Log.Messages`,
`Project.register_todo_before_clear` and `register_todo_after_clear`
(`audited`), `Alarms.predicate`, `Alarms.register` (`?predicate`),
`Alarmset.deliver`, `Cache_producer.has_preconditions`, `Callwise.part`,
`Compute_functions.Make.compute_and_cache_call`, `Safety_delivery.deliver`,
`Reach_delivery.deliver`, `Call_cache.report`.

**Argument (source inspection).**

*The design.* Four reviews each found a client that ran in an admitted hit
and that the test had not seen. The first two ran in the check of the
preconditions that a hit made at its call (the observers of `Base` and of
the origins); the last two ran when the delivery built the predicate of an
alarm that the entry did not hold (`Cil.typeForInsertedCast`, called by
`Cil.mkCast`, and the hooks on the table of logic functions, run when
`Logic_env.find_all_logic_functions` adds a built-in predicate). In each
case the hit ran an evaluator or a constructor of the kernel in place of
the body, and the test listed the interfaces known to be reached from it.
Two measures replace that list.

1. A hit runs less. It evaluates no `requires` clause: the lookup rejects
   the entries of a function whose call checks one (`preconditions`, see
   [Preconditions at a hit](#preconditions-at-a-hit)). It builds no
   predicate: the Safety part holds the predicate of each alarm, taken
   when the body registered the alarm
   ([The Safety part records the writes of the body](#the-safety-part-records-the-writes-of-the-body)).
   It checks no assigns clause: under `-from-verify-assigns`, the part of
   From is not audited, and the lookup rejects every candidate while its
   consumer is enabled
   ([The From part](cache-parts.md#the-from-part)). What is left writes
   recorded values in tables and prints lines.
2. What is left was read to its leaves, as listed below, and the lookup
   tests each interface found: the actions around the clearing of a
   project, the states that depend on the statuses and the hooks on their
   update, in addition to those tested before. The function of
   `Cil.typeForInsertedCast` and the hooks on the table of logic functions
   are tested too, although a hit no longer reaches them: an analysis of
   the body does.

*What a hit runs.* The steps, in order, from the test of the clients in
`Supplied_entries.Lookup.examine` to the return of
`Safety_delivery.delivered` in the hit branch of
`Compute_functions.Make.compute_and_cache_call`. For each step: the
functions read, then the *indirect calls* found in them, that is, the calls
of a function taken from a hook, a reference, a field of a record of
functions, a method or a functor argument that code outside the module can
set. An indirect call is named by its row in the table of interfaces. The
functions of the standard library, and the comparisons, hashes and tables
of the data structures of the kernel, are leaves; the exception is noted at
step 5.

1. *The rest of the lookup* (`examine`, `admit`, `Cache_entry.Make.find`).
   Reads of the state of the computation of Eva; `has_nested_call`, a walk
   of the list of the statements of the function; the comparison of the
   input of the call with the key of each candidate, on cvalue states; in
   `admit`, reads of tables of Eva (`Body_access.recursion_conflict`,
   `Builtins_malloc.has_automatic_bases`, `Builtins_watchpoint.active`,
   `Widen_generation.current`, `Body_access.warn_categories`,
   `Sweep_access.clear_input`), of options (`Function_calls.save_results`,
   `Eva_utils.skip_specifications`) and of the specification of the
   function (`Annotations.funspec`, which merges the clauses of the
   emitters in a new record and generates nothing);
   `Cache_part.supplies` and `Cache_part.restoration`, which use the
   answers that the predicates of the parts gave before the test.
   Indirect calls: none.
2. *The report of the lookup* (`Call_cache.lookup_supplied`,
   `Call_cache.report`). `Statistics.incr`, on tables that Eva does not
   export; one line of the category `cache` through the logger. Indirect
   calls: the logger (rows of the logger and of the message collector; the
   formatter and the printers, premise).
3. *The record of the hit in the collector* (`Call_cache.include_supplied`,
   `Body_access.include_hit`): a write in the recording of the body being
   analysed around the hit, if any. Indirect calls: none.
4. *The call hooks of Eva* (`apply_call_hooks` with `` `Reuse ``).
   Indirect calls: the call hooks (row).
5. *The delivery of the Safety part* (`Safety_delivery.skip_visits`,
   `Safety_delivery.deliver`). `skip_visits` adds the function to a table
   internal to Eva. For each write, `deliver` makes the callstack of the
   write the current one (`Current_callstack.with_callstack`, a reference)
   and calls one of four functions.
   - An alarm: `Alarmset.deliver`, then `Alarmset.register` with the
     predicate of the write. They record the write in the collector and in
     the Safety part of the body being recorded around the hit, if any
     (`Body_access.record`, `Safety_part.record_alarm`), call
     `Alarms.register`, and report the alarm once per analysis
     (`Alarm_cache.memo`, `report_alarm`: one warning through the logger,
     with Eva's printer of the annotation).
     `Alarms.register`, given a predicate, reads and writes the tables of
     the alarms, which `alarms.ml` does not export
     (`to_annot_aux`, `find_alarm_in_emitters`), wraps the predicate in a
     new annotation (`Logic_const.toplevel_predicate`,
     `Logic_const.new_code_annotation`) and, when the alarm is not yet
     registered, adds the annotation: `Emitter.get`, `alarm_kf_stmt`
     (`Kernel_function.find_englobing_kf`), `Annotations.add_code_annot`,
     `Rank.next`. `Annotations.add_code_annot` runs the branch of an
     assertion of `do_add_code_annot`: `extend_name`,
     `Property.ip_of_code_annot`, `Property_status.register` for the new
     property, a write in the table of the annotations of the statement;
     then the hooks on the changes of the annotations. In every case
     `Alarms.register` then emits the status
     (`Property.ip_of_code_annot_single`, `Property_status.emit`).
     It does not call `Alarms.create_predicate`, which only
     `to_annot_aux` without a predicate and `Alarms.predicate` call.
   - A status: `Safety_part.emit_status`, then
     `Property_status.emit ~distinct:true`.
   - A message: `Safety_part.status_message`, one result or one warning
     through the logger, printed once.
   - A red context: `Red_statuses.add_red_context`, a write in a table
     internal to Eva, then the hooks of red statuses.

   `Property_status.emit` (`unsafe_emit_and_get`) prints a line of the
   kernel when the debug key of the emissions is enabled, reads the table
   of the statuses and, when the status of the emitter changes: runs the
   hooks on removal of that table for the previous status
   (`Status.apply_hooks_on_remove`); clears the states that depend on the
   statuses (`Project.clear ~selection`), which prints a line of the
   project library under debug, runs the actions registered before the
   clearing of a project, then for each state its function `clear`, the
   hooks on its update and its function `set`
   (`State_builder.Register.clear`, `update_with`), then the actions
   registered after the clearing; writes the status and the table of the
   hypotheses; for an invalid status, takes the property of reachability
   of the statement (`Property.ip_reachable_ppt`) and emits its validity
   through the same function when it is a tautology; and runs the hooks on
   a new status. It registers a property that is not yet registered
   (`register`), which runs the hooks on a new property. When the status
   of the emitter does not change, it does none of this.

   Indirect calls: the hooks on a new property and on a new status (row);
   the hooks on the changes of the annotations (row), whose audited client
   runs the observers of `Hook.Opaque` (row); the actions before and after
   the clearing of a project (row); the functions and the hooks on update
   of the states that depend on the statuses (row); the hooks of red
   statuses (row); the logger (rows; premise for the formatter and the
   printers); the hooks on removal of the table of the statuses, a table
   that `property_status.ml` does not export and on which that file
   registers two functions, the removal of the property from the table of
   the hypotheses and the hooks on a new status (row); the forward
   reference `Kernel_function.find_englobing_kf`, and those that the
   comparisons of `Cil_datatype` on alarms and properties use (row of the
   forward references, outside); the hooks of change of the tables
   internal to Eva and to the kernel (rows, outside).
6. *The delivery of the Reach part* (`Reach_delivery.deliver`): writes in
   five tables internal to Eva
   ([A hit delivers the Reach part as recorded joins](reach.md#a-hit-delivers-the-reach-part-as-recorded-joins)).
   Indirect calls: the hooks of change of these tables (rows, outside).
7. *The line of the reuse* (`Self.feedback` with the name of the
   function). Indirect calls: the logger, as at step 2.
8. *The restoration of the parts* (`Cache_part.restore`): the restore
   function of each part of the entry whose consumer is enabled, all
   audited by the answers taken before the test. Those of the tree:
   `Callwise.restore_froms`, which records the dependencies in tables that
   From does not export (`end_record`); the restore function of Inout,
   which writes its table and runs the clients of its hook on the inputs
   and outputs of a call
   ([The restoration of a part runs audited clients only](cache-parts.md#the-restoration-of-a-part-runs-audited-clients-only)).
   Indirect calls: the restore functions and the clients of the hook of
   Inout (row of the parts).
9. *The update of the summary* (`Safety_delivery.delivered`,
   `Summary.FunctionStats.recompute`): reads of the tables of statuses,
   alarms and annotations and of the reachability of the statements, then
   a write in the table of the statistics by function. Indirect calls: the
   subscribers of the statistics (row).

The Reach part is delivered after the Safety part, and before the line of
the reuse and the restoration of the parts. From the end of the Reach
delivery to the end of the restoration, the points of the hit are recorded
and the results of the call in From and Inout are not yet restored. What
runs in that interval is steps 7 and 8: the lookup admits the hit only when
the clients of these interfaces are audited, and none of the audited
clients of the tree that run there (the list below: the message collector,
the observers of the collector, the restore functions of the parts of From
and Inout and Eva's client of the hook of Inout) reads the tables of the
Reach delivery or the results of From and Inout. No client therefore
observes that intermediate state. The function is recorded among those
whose visits a hit skipped before both deliveries: a request of the
results of From and Inout by function made in the interval would be
refused, as after the hit.

An analysis of the body runs the same interfaces, and also, at each
statement, the statement hooks of Eva, a change of the current location and
`Async.yield`; at each call that it makes, the statistics of performance by
callstack; when it emits an alarm that is not yet registered, the
construction of its predicate (`Alarms.create_predicate`), with
`Cil.typeForInsertedCast` and, at the first use of a built-in predicate,
the hooks on the table of logic functions; when it evaluates a term or a
predicate, the observers of `Base` and of the origins; and after the body,
the call results hooks, the observers of the Safety part, of the Reach part
and of the results of the collector. A hit of memexec, which no analysis
with supplied entries has, still checks the preconditions and runs the
call results hooks.

*The interfaces.* One row for each interface through which code registered
by a plug-in can run, found by the reading above and by the search
described below. "Hit" says whether a hit reaches the interface between the
test and the return of `Safety_delivery.delivered`; "Fresh" whether an
analysis of the body reaches it. The treatments are: "test", the lookup
tests the interface, with the flag of an audited client if any and the
accessor that `unaudited_clients` calls; "argued", neither a hit nor an
analysis of the body reaches it, for the reason given; "premise", the
output premise of the supplier (`supplied_entries.mli`), see the routes
below; "outside", outside the guarantee.

| Interface | Hit | Fresh | Treatment |
| --- | --- | --- | --- |
| Call hooks of Eva (`Cvalue_callbacks.register_call_hook`) | yes, with `` `Reuse `` (step 4) | yes | test, flag `cache_protocol` (`Cvalue_callbacks.unaudited_hooks`) |
| Call results hooks of Eva (`register_call_results_hook`) | no | yes | test, flag `cache_protocol` (same accessor) |
| Statement hooks of Eva (`register_statement_hook`) | no | yes | test, flag `classified` (same accessor) |
| Hooks of red statuses (`Red_statuses.register_hook`) | yes (step 5) | yes | test, no flag (`Red_statuses.has_hooks`) |
| New property, new status (`Property_status.register_property_add_hook`, `register_status_update_hook`) | yes (step 5) | yes | test, no flag (`Property_status.has_add_or_update_hooks`) |
| Changes of the annotations (`Annotations.add_hook_on_change`) | yes, at the registration of an alarm (step 5) | yes | test, flag `audited` (`Annotations.has_unaudited_hooks_on_change`) |
| Actions before and after the clearing of a project (`Project.register_todo_before_clear`, `register_todo_after_clear`) | yes, at each emission that changes a status (step 5) | yes | test, flag `audited` (`Project.has_unaudited_clear_hooks`) |
| States that depend on the statuses (a state built with `Property_status.self` among its dependencies, directly or not): its functions `clear` and `set`, and the hooks on its update (`add_hook_on_update` of the state, `State.add_hook_on_update`) | yes, at each emission that changes a status (step 5) | yes | test: a state whose unique name is not one of the four of the kernel or, when Report is loaded, of the three of Report, or a hook on the update of any of them (`Supplied_entries.unaudited_status_dependents`, `State.has_hooks_on_update`) |
| Logger: listeners (`Log.add_listener`), `register` of `Log.Messages`, observers of the history (`Log.on_history_access`) | yes (steps 2, 5 and 7) | yes | test, flag `audited` (`Log.unaudited_clients`) |
| Message collector (`Messages.add_hook`) | yes (steps 2, 5 and 7) | yes | test, no flag (`Messages.has_hooks`) |
| Parts (`Cache_part.register`), with the clients that their restoration runs (`Inout`'s `register_call_hook`) | yes, the restoration of the parts whose consumer is enabled (step 8) | `provide` only | test, predicate `audited` (`Cache_part.unaudited_clients`) |
| Readers of the statement states (`Cache_part.register_state_reader`) | the predicate, before the test | no | `consumer`; the rules of the predicates (`cache_part.mli`) |
| Subscribers of the statistics by function (`Summary.FunctionStats.add_hook_on_change`) | yes (step 9) | yes | test, flag `audited` (`Safety_delivery.unaudited_subscribers`) |
| Observers of the clients of the kernel hooks (`Hook.Opaque.on_call`) | yes, through each hook above that the kernel or Eva wraps | yes | test, flag `audited` (`Hook.Opaque.has_unaudited_observers`) |
| Reads of the metadata and updates of the validity of allocated blocks (`Base.observe_metadata_reads`, `Base.observe_validity_updates`) | not established for the reads: a hit evaluates nothing, and the operations of step 1 on cvalue states were not read for them; in `alone.c` the audited observer is called during no delivery; no update | yes | test, flag `audited` kept by the physical identity of the function, in a registry that holds the functions weakly (`Base.has_unaudited_observers`) |
| Accesses to the history of the origins (`Origin.on_history_access`) | not established, as for `Base` | yes | test, flag `audited` (`Origin.has_unaudited_observers`) |
| The type of an inserted cast (`Cil.typeForInsertedCast`, a reference to a function that `Cil.mkCast` calls) | no: a hit builds no expression, term or predicate | yes: the predicate of an alarm on an unaligned pointer is built with a cast, and the evaluation inserts casts | test: a function other than the default one (`Cil.has_inserted_cast_hook`) |
| Hooks on the table of logic functions (`Logic_env.Logic_info.add_hook_on_change`) | no: a hit adds no logic function | yes, when the predicate of an alarm uses a built-in predicate for the first time (`Logic_env.find_all_logic_functions`) | test, no flag (`Logic_env.has_hooks_on_logic_functions`) |
| Daemons (`Async.on_progress`, `while_progress`, `with_progress`) | no: a hit does not call `Async.yield` | yes, at each statement | test, no flag (`Async.has_daemons`) |
| Current location (`Current_loc.add_hook_on_change`) | no: the files of the steps call no visitor of `Cil` and do not set the location (search below); `Alarmset` reads it | yes, at each statement | test, no flag (`Current_loc.has_hooks_on_change`) |
| Statistics of performance by callstack (`Eva.Eva_perf.StatByCallstack.add_hook_on_change`) | no; the start and end of the call run outside this interval, with another duration | yes, at each call that the body makes | test, no flag (`Eva_perf.has_hooks_on_change`) |
| Observers of the Safety part (`Eva.Safety_part.on_result`) | no | yes | test, flag `audited` (`Safety_part.has_unaudited_observers`) |
| Observers of the Reach part (`Eva.Reach_part.on_result`) | no: they run when the capture of a body ends | yes | test, flag `audited` (`Reach_part.has_unaudited_observers`) |
| Observers of the results of the collector (`Eva.Body_access.on_result`) | no | yes, with `-eva-cache-collect` | test, flag `audited` (`Body_access.Result.has_unaudited_observers`) |
| Generation modes of specifications (`Populate_spec.register`) | no: a hit of a supplied entry does not complete the specification, and `Annotations.funspec`, which the lookup calls, generates nothing | no | argued: `populate_funspec` without `do_body` generates nothing for a function that has a body |
| Logic builtins (`Logic_builtin.register`, `Logic_builtin.add`) | no | no | argued: they declare logic symbols, which the typing of ACSL reads and, in an analysis of the body, the construction of the predicate of an alarm; the evaluation of terms interprets the logic functions that it knows by name, with fixed functions of Eva (`Eval_terms`, `Builtins_string`) |
| ACSL extensions (`Acsl_extension.register_behavior`, `register_code_annot*`, `register_global*`) | their printers, when a message prints an extended clause | the same | argued for the typers, run when the AST is typed, and the visitors, run when a visitor of `Cil` visits an extended clause: a hit runs no visitor; premise for the printers. Eva's own extensions (`Eva_annotations`) are read by the iterator, during an analysis of the body only, with fixed interpretations |
| Builtins (`Eva.Builtins.register_builtin`) | no | at a call that the body makes | argued: the producer refuses such a body (`builtin`); the supplier owes it for an entry given to `supply` |
| Domains (`Eva.Domain.register`) | no | no | argued: a registered domain runs only when it is enabled, and an enabled domain other than cvalue rejects every candidate with `product`; the hooks that transform the abstractions (`Abstractions.Hooks.register`, `Engine.register_hook`) are internal to Eva (outside), and those of the tree return the abstractions unchanged unless their own domain or value is enabled |
| Analysis hooks (`Cvalue_callbacks.register_at_start_hook`, `Analysis.register_computation_hook`) | no | no | argued: they run at the start, the end or the reset of an analysis; a reset during an analysis rejects with `analysis-reset` |
| Compute hooks of the statistics (`Eva.Statistics.add_compute_hook`) | no | no | argued: they run when the statistics are exported; `Statistics.incr` writes in tables that Eva does not export |
| Hooks on the options (`add_set_hook`, `add_update_hook` of a parameter) | no | no | argued: no option is set by Eva, From, Inout or the services of the kernel during a call (search below); Eva sets one in the outputs of the analysis of threads, which rejects with `consumer` |
| AST and projects (`Ast.add_hook_on_update`, `Ast.apply_after_computed`, the hooks of `Cabs2cil` and `Frontc`, `Project.register_create_hook` and the hooks of `Project` other than those around a clearing) | no | no | argued: no AST is built or changed, and the only project operation is the clearing of the states that depend on the statuses (rows above); a change of the current project refuses the recordings |
| Removals (`Property_status.register_property_remove_hook`, the removal hooks of `Emitter.Make_table`) | no | no | argued: no property and no annotation is removed during a call. The emission of a status runs the removal hooks of the table of the statuses for the previous status of the emitter; `property_status.ml` does not export that table, and registers two functions on it: the removal of the property from the table of the hypotheses, and the hooks on a new status, which are tested |
| Stages of the command line (`Cmdline.run_after_*`, `Boot.Main`), `Task.on_idle` | no | no | argued: outside an analysis |
| Dynamic registrations (`Dynamic.register`, read by `Eva_dynamic` with `Dynamic.get`) | no | no | argued: Eva reads Scope, Callgraph and the outputs of Inout after the analysis, and registers its client of Inout once, as audited |
| State hooks of Callgraph (`StateHook` of `Cg` and `Services`) | no | no | argued: the call graph is not computed during a call |
| State hooks of the other exported states of the kernel (the other tables of `Logic_env`, `Ast_diff`, `Parameter_state.Is_set`, `Cil_builtins`), and the hooks on a whole update (`add_hook_on_update`) of the states that do not depend on the statuses, `Summary.FunctionStats` and `StatByCallstack` included | no | no | argued: none of these states is written during a call, and a whole update is a project operation (copy, load, clear); the only one during a call is the clearing of the states that depend on the statuses, which has its own row |
| Hooks of the server interface of Eva (`Update.add_computation_hook`, `add_callstack_hook`, `add_hook`; `Taint_requests.register_hook`) | no | no | argued: they run at a change of the computation state and of the callstacks selected through the server; the taint hook needs the taint domain, which rejects with `product` |
| Printers: `Printer.update_printer`, the printing references of `Cil` and `Cil_datatype`, the printers of `Acsl_extension`; the formatter (`Log.set_formatter`), the history test (`Log.check_not_yet`) and the output sinks of the logger | yes | yes, other lines | premise |
| Forward references of the kernel (`ref` values of an interface, set by other kernel modules: `Log.set_current_loc`, those of `Globals`, `Cil_datatype`, `Kernel_log` and `Parameter_builder`) | some, such as `Globals.find_englobing_kf` and `Cil_datatype.punrollType` | yes | outside: each is documented as internal ("do not use outside of this module", "Internal API", an alert); a replacement replaces part of the kernel, as one of an `Eva__*` unit does in Eva |
| The registry of the states (`State.create`, `State.delete`, under "Internals" in `state.mli`) | no | no | outside: a state deleted and created again under the unique name of a state of the kernel would pass the test by name; `state.mli` reserves both functions to the project library, and `State_builder` gives a name already taken a new unique name |
| Hooks of change of the tables of the kernel that a hit writes (the tables of `Alarms`, of the annotations of a statement in `Annotations`, of the statuses and of the hypotheses in `Property_status`, of `Emitter`) | yes (step 5) | yes | outside: the modules of these tables are not in the interfaces of their compilation units, and the search on hooks of states finds no client |
| Hooks of change of the points reached by the hits (`Points` in `Reach_delivery`) | yes, at the delivery of the Reach part | no | outside: the module of the table is not in `reach_delivery.mli`, and the search on hooks of states finds no client |
| Hooks of change of the functions of unknown reachability (`Unknown` in `Reach_delivery`) | yes, at a delivery under `-eva-no-results-domain cvalue` | no | outside: the same |
| Hooks of change of the outcomes of the guards (`Conditions_table` in `Iterator`) | yes, at the delivery of the Reach part | yes | outside: the same, for `iterator.mli` |
| Hooks of change of the zones read and written (the table of `Inout_access`) | yes, at the delivery of the Reach part | yes | outside: the same, for `inout_access.mli` |
| Hooks of change of the callers (the table `Callers` of `Function_calls`) | yes, at the delivery of the Reach part | yes | outside: the same, for `function_calls.mli` |
| Internal modules of Eva (`Eva__Private`, the other `Eva__*` units: the tables of red contexts and of skipped visits, the computation state, `Safety_delivery.on_delivered`) | yes | yes | outside; `on_delivered` is one-shot |

*How the reading and the search were done.* The steps were read in these
files, each function to the calls that it makes:
`supplied_entries.ml`, `cache_entry.ml`, `cache_part.ml`,
`cache_producer.ml`, `call_cache.ml`, `compute_functions.ml`,
`safety_delivery.ml`, `safety_part.ml`, `alarmset.ml`, `red_statuses.ml`,
`reach_delivery.ml` and `summary.ml` of Eva; `callwise.ml` of From and
`operational_inputs.ml` of Inout, for their restore functions; `alarms.ml`,
`annotations.ml`, `property_status.ml`, `emitter.ml`, `project.ml` and
`state_builder.ml` of the kernel. The logger (`log.ml`), the hooks
(`hook.ml`), the collector (`body_access.ml`) and the message collector
(`messages.ml`) were read for the earlier versions of this entry, and their
rows are unchanged. A reviewer can check that the files of the steps make no
other kind of indirect call, and that a hit reaches no construction of a
predicate:

```sh
# visitors, changes of location, yields and dynamic accesses in the steps
git grep -nE 'Current_loc\.|visitCil|Cil\.visit|Visitor\.|inherit .*[vV]isitor|Async\.yield|Dynamic\.get' -- plugins/eva/src/alarmset.ml plugins/eva/src/engine/safety_delivery.ml plugins/eva/src/engine/safety_part.ml plugins/eva/src/engine/reach_delivery.ml plugins/eva/src/engine/reach_part.ml plugins/eva/src/engine/call_cache.ml plugins/eva/src/engine/supplied_entries.ml plugins/eva/src/engine/cache_entry.ml plugins/eva/src/engine/cache_part.ml plugins/eva/src/engine/cache_producer.ml plugins/eva/src/utils/red_statuses.ml plugins/eva/src/utils/summary.ml plugins/from/src/callwise.ml src/kernel/services/ast_data/alarms.ml src/kernel/services/ast_data/property_status.ml src/kernel/services/ast_data/annotations.ml src/kernel/services/plugin_entry_points/emitter.ml src/lib/project/project.ml src/lib/project/state_builder.ml
# the callers of the construction of a predicate, and of the evaluation of
# the clauses of a specification
git grep -nE 'create_predicate|Alarms\.predicate|Alarms\.to_annot' -- 'src/*.ml' 'plugins/eva/src/*.ml'
git grep -nE 'check_fct_preconditions|verify_assigns|check_fct_assigns' -- 'plugins/eva/src/*.ml' 'plugins/from/src/*.ml' 'plugins/inout/src/*.ml'
# the hooks applied in the kernel files of step 5
git grep -nE '\.apply\b|apply_hooks_on_remove|Project\.clear' -- src/kernel/services/ast_data/alarms.ml src/kernel/services/ast_data/property_status.ml src/kernel/services/ast_data/annotations.ml src/lib/project/project.ml src/lib/project/state_builder.ml
```

The first search finds a read of the current location in `alarmset.ml`, the
accessor of the test, and a visitor in `Annotations.dependencies_of_global`,
which the addition of a code annotation does not call. The table was built
from this reading and from searches of the tree by mechanism, excluding the
tests:

```sh
# registration functions, observers, listeners and daemons
git grep -nE '\badd_hook\w*|\bregister\w*\s*:|^\s*val (register|add)\w*|\bextend\b|observe|on_call|add_listener|on_progress' -- 'src/*.mli' 'plugins/*.mli' 'plugins/*_sig.ml' ':!*/tests/*'
# instances of hooks
git grep -nE 'Hook\.(Build|Make|Fold|Build_ordered|Make_ordered|Fold_ordered)\b|Hook\.Opaque' -- 'src/*.ml' 'plugins/*.ml' ':!*/tests/*'
# hooks on states, and the exported states
git grep -nE 'add_hook_on_(change|update|remove)' -- 'src/*.ml' 'plugins/*.ml' ':!*/tests/*'
git grep -nE 'State_builder\.(Ref|Hashtbl|Option_ref|List_ref|Counter|Proxy|Set_ref)' -- 'src/*.mli' 'plugins/*.mli'
# forward references and assignments of functions
git grep -nE ':.*->.*\) ref\b|: *\(.*->.*\) option ref|_ref *:' -- 'src/*.mli' 'plugins/*.mli'
git grep -nE ':= *fun\b' -- 'src/*.ml' 'plugins/*.ml' ':!*/tests/*'
# yields and dynamic registrations
git grep -nE 'Async\.(yield|on_progress|while_progress|with_progress)' -- 'src/*.ml' 'plugins/*.ml'
git grep -nE 'Dynamic\.(get|register)|Eva_dynamic\.' -- 'src/*.ml' 'plugins/*.ml'
# writes of options and of the current location, removals of properties
git grep -nE '\b(Kernel|Parameters|Self|From_parameters|Inout_parameters)\.[A-Z][A-Za-z_]*\.(set|on|off|unsafe_set|clear)\b' -- 'src/*.ml' 'plugins/eva/*.ml' 'plugins/from/*.ml' 'plugins/inout/*.ml' ':!*/tests/*'
git grep -nE 'Current_loc\.(set|with_loc)|UpdatedCurrentLoc' -- 'src/*.ml' 'plugins/*.ml'
git grep -nE 'Property_status\.remove|Annotations\.remove|remove_code_annot|remove_alarm' -- 'src/*.ml' 'plugins/*.ml'
```

with the list of the modules that `Eva.ml` exports. Each hit of these
searches was classified by whether it is exported and whether code on the
hit path or on the path of an analysis of the body calls it. Not rows:
instances that are not exported (the hook of From on its callwise results,
the hooks of `Statistics` other than `add_compute_hook`, the tables of
`Mt_summary` and of `Self`, the four assignments `:= fun`); functions that
add data rather than code (the `add` functions of data structures, of
annotations and of the logic environment, apart from the table of logic
functions, which has a row); the registration functions of
the plug-ins that neither the kernel nor Eva, From and Inout call during an
analysis (WP, E-ACSL, Region, Slicing, Pdg, Dive, Aorai and the others),
which a hit or an analysis of a body reaches only through an interface
listed here; and functions run when a process exits. The writes of options
found are those of the outputs of the analysis of threads, of the
processing of the command line and of the boot, of the typing, of the entry
point (`Globals`), of the compilation database and of the saving of a
session, and the writes of the computation state of Eva at the start and
the end of an analysis; the removals of
properties are in the copy visitors, the inlining, the typing, the removal
of the alarms of an emitter and the export of the results of Eva, none
during a call.

*The test.* Each registration function marked "test" records whether it
registered a client without the flag of an audited client (`cache_protocol`
or `classified` for the hooks of Eva, `audited` for the others that have
one, the predicate `audited` for the parts); for the others, any
registration counts. A client cannot be removed, apart from a daemon of
`Async`, which counts while it is registered; an observer of `Base` removed
since counts. The function of `Cil.typeForInsertedCast` counts while it is
installed. `unaudited_clients` is the disjunction of the twenty-one
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
nothing and write in no table. Before the two passes (at the commit now
`cbf089bcb4` (before the rebase onto #48)), a predicate `needed` or of a reader
of the statement states that registered a client of Inout after the audit of
the part of Inout let the first call hit, and the client ran at its
restoration.

*From the test to the end of the delivery.* The client code that runs
between the test and the end of `Safety_delivery.delivered` is the one
reached by the indirect calls of the nine steps.
- The restore functions of the parts run only for the parts whose answers
  say that their consumer is enabled and that they are audited: they
  belong to audited registrations. `Cache_part.provide` runs in the
  analysis of a body, never at a hit. The parts have no printer, and the
  reasons of rejection and refusal are printed by Eva's own functions. The
  check that the function of an entry belongs to the current project runs
  when the entry is supplied, not at the lookup.
- Every other indirect call is a row of the table with the treatment
  "test", "premise" or "outside".
- No step registers a client, sets an option or loads a plug-in: what the
  test saw holds until the end of the delivery, unless an audited client
  changes it, which the audits below exclude.

After `Safety_delivery.delivered`, the engine returns the exit states of
the entry to the code that called it, as it returns those of an analysed
body: what follows is the code of the return of a call, which is not
specific to a hit.

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
  the body being recorded around the hit, if any. No regression makes a
  hit run the observer of the metadata: a hit checks no precondition.
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
  false, and the statistics count as reached the statements that an
  analysed call or a hit reaches, from the points that the hits deliver,
  as with caching disabled
  ([The passes after the analysis read the points reached by hits](reach.md#the-passes-after-the-analysis-read-the-points-reached-by-hits));
  during the analysis, the results answer that every statement is
  reachable, with or without hits. On
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
- The action of the server before the clearing of a project
  (`States.synchronize`, registered with `audited`), one for each array
  of the server, loaded with the server as the client of the annotations
  is. It removes the content that the server keeps for the array in the
  project, which only the requests of the server read. The emission of a
  status runs it at a hit as in an analysis of the body. No other action
  around a clearing is registered in the tree.
- The states that depend on the statuses and that the test knows by name.
  Those of the kernel are the graph of consolidation, the consolidated
  statuses, the hypotheses and the valid cycles (`property_status.ml`);
  the emission clears the first two, which the next request of a
  consolidated status computes again from the emitted statuses, and
  leaves the last two (`linked_to_self`). Those of Report, counted when
  Report is loaded, are the three flags of `State_builder.apply_once`
  that make it classify, print and dump its report again after a change
  of the statuses. Their functions `clear` and `set` are those of
  `State_builder`, and they run at a hit as in an analysis of the body. A
  state with one of the names of Report counts as not audited while
  Report is not loaded, and a second state cannot take the unique name of
  a registered one (`State.unique_name_from_name`). Metrics has a state
  that depends on the statuses: it is not in the list, and Metrics
  rejects every candidate as a reader of the statement states
  (`consumer`) before this test.

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

*Outside the guarantee.* The claim does not cover the following, and a
reviewer who looks for a client that the test does not see should start
here.

- *Clients registered as audited.* A client outside the tree registered
  with the flag of an audited client is trusted; for an observer of
  `Base`, the flag is kept with the function, and a function installed
  once with the flag is trusted when it is installed again without it.
  The observers of the collector, of the Safety part and of the Reach
  part registered as audited are test devices of the cache, through which
  a test reads the dispositions; no plug-in of the tree registers one, and
  `same.c` uses one, registered as audited, to change a setting between
  two calls, which the audit of a test device does not cover.
- *The output premise.* The rows "premise" of the table are replaceable
  parts that are not registrations and that the test does not see: the
  formatter installed with `Log.set_formatter`, the history test
  `Log.check_not_yet`, the output sinks of the logger, and the printers
  that a plug-in replaces or extends (`Printer.update_printer`, the
  printing references of `Cil` and `Cil_datatype`, the printers of
  `Acsl_extension`), which format the elements of the AST named in the
  messages, at a hit as in an analysis of the body, in other lines. A
  replacement that acts on what it prints or tests can tell a hit from a
  fresh call without declaring itself audited: with a formatter that sets
  `alarm` to `abort` when it sees the disposition of a hit, the delivery
  stops at the first status message where the run with caching disabled
  completes with `r1 = 9` and `r2 = 8`. No plug-in of the tree installs
  such a replacement. The guarantee of this entry is for the logger and
  the printers of the tree with output sinks that do not act on the
  analysis; the supplier owes it (`supplied_entries.mli`).
- *The parts of the kernel documented as internal.* The forward
  references of the kernel, which a hit calls (`Globals.find_englobing_kf`
  through `Kernel_function.find_englobing_kf`, those that the comparisons
  of `Cil_datatype` use, `Log.set_current_loc`), and the registry of the
  states (`State.create`, `State.delete`): each is documented as internal
  to the kernel or to the project library. A module that sets one
  replaces part of the kernel.
- *The internal modules of Eva* (`Eva__Private` and the other `Eva__*`
  units, which the build exposes), including the hooks of the internal
  tables that a hit changes (`State_builder` hooks of the table of red
  contexts, of the functions with skipped visits). A module that reaches
  them can call or replace what the engine relies on. The installation of
  the update of the summary is one-shot, so that such a module cannot
  replace it silently: a second installation raises.
- *The hooks of change of tables that are not exported.* A hit writes in
  tables of the kernel (alarms, annotations of a statement, statuses,
  hypotheses, emitters) and of Eva (the five tables of the Reach
  delivery, the red contexts, the functions with skipped visits) whose
  modules are not in the interfaces of their compilation units: no code
  outside the unit can add a hook of change (`add_hook_on_change`) on
  them, and the search on the hooks of states above finds none. The
  hooks on a whole update (`State.add_hook_on_update`), which take the
  exported value `self` of a state, run at a project operation, not at a
  write; the only project operation of a hit is the clearing of the
  states that depend on the statuses, and the test covers the hooks on
  the update of each of these
  ([A hit delivers the Reach part as recorded joins](reach.md#a-hit-delivers-the-reach-part-as-recorded-joins)).
- *What was not read.* The operations of step 1 on cvalue states (the
  comparison of the input with a key, the exit states of the hit) were
  not read for reads of the metadata of the blocks or for the creation
  of imprecise values; the lookup tests the observers of both. The
  functions of the standard library (`Format`, `Hashtbl`, `Str`, `Weak`)
  were taken as leaves. The logger, the collector and the message
  collector were read for the earlier versions of this entry, not again
  for this one.
- *The same configuration.* The entries and the hit belong to one
  process, one project and one AST: the predicate of an alarm kept in an
  entry names the logic functions and the variables of that AST. Entries
  that cross analyses are
  [issue #59](https://github.com/nyandrianinamamy/frama-c/issues/59).

The observers of the Reach part (`Reach_part.on_result`) run when the
capture of a body ends, after its analysis, and never at a hit; as for the
Safety part, one registered without `audited` rejects every candidate, and
no plug-in of the tree registers one (`cache-reach.t` registers one as
audited).

**Evidence (executed).** `cache-safety.t`. The scenarios on `inside.c`,
`interleave.c`, `pre-route.c`, `later.c`, `repeat.c` and `second.c` are
compared with the run with caching disabled and the same clients, on the
tables of statuses, alarms and red contexts and on the state at the end of
`main`; the loops over the clients, `alone.c` and `metadata.c` count the
hits, the rejections and the calls of the observers only:

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
  rejected for `callback` and the analysis ends with `out = 5`, as with
  caching disabled; when a hit evaluated the preconditions, the comparison
  after the delivery stopped the hit. Without the client, the entry is
  rejected for `preconditions`: no hit runs on this route any more.
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
- One client of each of the interfaces found by the sweep of the
  previous version, registered after the analysis from `producer` of
  `safety.c` (`opaque`, `metadata`, `validity`, `origin`, `daemon`,
  `location`, `perf`, `safety-result`, `reach-result`,
  `collector-result`), makes both calls of `body` reject the entry with
  `callback`.
- One client of each of the interfaces found by the reading of this
  version, in the same scenario, makes both calls of `body` reject the
  entry with `callback`: an action before and one after the clearing of a
  project (`clear-before`, `clear-after`); a state that depends on the
  statuses (`status-state`); a state with the name of one of Report,
  while Report is not loaded (`status-report`); a hook on the update of
  the consolidated statuses of the kernel (`status-update`); a function
  installed in `Cil.typeForInsertedCast` (`cast`); a hook on the table of
  logic functions (`logic`).
- `prepared.c`: `body` has an alarm on an unaligned pointer, whose
  predicate the kernel builds with a cast, and an alarm on a float that is
  not finite, whose predicate uses a built-in predicate. The call of
  `body` hits; the test compares, by physical equality, the predicate of
  the annotation that the hit registers with the predicate of the write
  of the entry: `registered with the predicate of the entry: true` for
  both alarms. The tables of statuses, alarms and red contexts and the
  state at the end of `main` (`r2 = 8`) are those of the run with caching
  disabled. Before the Safety part held the predicates, a review replayed
  this program with a function installed in `Cil.typeForInsertedCast`,
  and with a hook on the table of logic functions, each of which stopped
  the analysis when called: the hit ran it, and `main` had no state where
  the run with caching disabled gives `r2 = 8` (replayed on the build of
  `80902ea99f`, before the rebase onto `d11d693ddc`). The same two
  programs of the review, replayed on the build of `416e9fe167` with the
  client installed before the analysis or by a predicate during the
  lookup: the entry is rejected with `callback`, no call hits, and `main`
  ends with `r2 = 8`.
- `alone.c` (`safety.c` without the first call of `body`), with the server
  loaded after the analysis from `producer`: the hit on `body` registers an
  alarm, which runs the client of the server on the annotations through
  `Hook.Opaque.wrap`. An observer of `Hook.Opaque` registered without an
  audit makes the call reject the entry (`hits on body: 0, rejected for
  callback: 1`) and is not called during a delivery; registered as
  audited, the call hits and the observer is called once during the
  delivery. Before the test of `Hook.Opaque` (at the commit now `cbf089bcb4`
  (before the rebase onto #48)), a review observed the observer without an
  audit running at the hit after the visits were skipped. On `alone.c`, the
  status of the division alarm at the end is unknown after the hit, where the
  run with caching disabled gives it the final status invalid (executed at
  `95016e62ee` with the audited observer, outside the test suite): `body` is
  called from `main` only through the hit, and the refinement of the statuses
  after the analysis evaluates the alarm in the state top of the callstack of
  the hit, from which it concludes nothing
  ([The passes after the analysis read the points reached by hits](reach.md#the-passes-after-the-analysis-read-the-points-reached-by-hits)).
- `metadata.c`, with `-eva-alloc-returns-null`: the precondition of `pre`
  reads the validity of an allocated block, and a hand-written entry is a
  candidate at the second call. An observer of the reads of the metadata
  registered without an audit makes both calls reject the entry (`hits on
  pre: 0, rejected for callback: 2`) and is not called during a delivery;
  registered as audited, it rejects none: the entry is rejected for
  `preconditions` at the second call, and the observer is called during
  no delivery. When a hit checked the preconditions (at the commit now
  `cbf089bcb4` (before the rebase onto #48), before the test of `Base`), a
  review observed the observer without an audit running in the admitted
  hit, before the visits were skipped. On `alone.c`, where `body` has no
  precondition, the call hits with the audited observer, which is called
  during no delivery.
- The registry of the audited observers of `Base` holds them weakly: 128
  audited observers of 64 KiB each, installed and removed in turn, are
  collected (`removed and still alive: 0 of 128`). An audited observer
  installed again without the flag does not count as a client that is not
  audited; another observer installed without the flag counts, and counts
  once removed. Before, the registry was a list that held every function
  installed with the flag: a review measured the closures of removed
  observers kept alive.

In `cache-parts.t`:

- Scenario `predicate`: a part never needed and not audited, whose
  predicate registers a call hook of Eva at its first or at its second
  evaluation in the analysis with the supplied entries. At the first, the
  three calls to `copy` read `callback` for their three candidates; at the
  second, the first call hits and the two others read `callback`. The hook
  receives no call with `` `Reuse ``, and the predicate runs 7 times, once
  for each lookup with candidates. At the commit now `7dfdd31b87` (before the
  rebase onto #48), before the answers were taken once, both gave `hits 1`, one
  call with `` `Reuse `` and 3 evaluations.
- Scenario `predicate` with `EVA_TEST_CACHE_PARTS_CLIENT=inout`: the
  predicate `needed` of a part registered after the parts of From and
  Inout registers a client of the hook of Inout on its first evaluation.
  The three calls to `copy` read `callback` for their three candidates,
  and the client is called 0 times after a hit on `copy`. With
  `EVA_TEST_CACHE_PARTS_CARRIER=reader`, the predicate of a reader of the
  statement states registers it, with the same results. At the commit now
  `cbf089bcb4` (before the rebase onto #48), when the audit of the part of
  Inout ran before these predicates, both gave `copy: hits 1, rejected for
  callback 6`, and the client was called 10 times after the hit.
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
  disabled read `complete true, reached 2`. At the commit now `7dfdd31b87`
  (before the rebase onto #48), the subscriber without an audit let the three
  calls hit.
- Scenario `replace-summary`: a second installation through
  `Eva__Private.Safety_delivery.on_delivered` is refused, and the three
  calls to `copy` hit. At the commit now `7dfdd31b87` (before the rebase onto
  #48), a module outside the tree replaced it, and its function ran at the
  seven hits of `parts.c`.
- The scenarios with the server loaded and not started keep their hits
  (`copy 3`): the server registers no subscription to the statistics.

Mutations of this version, each applied alone, run against the cram test
named and reverted. `cache-parts.t`, `cache-reach.t` and `cache-safety.t`
pass from scratch on `da5358f4c8` (`bash dev/cram-fresh.sh`), and each
mutation makes its test fail on the lines quoted.

- Each of the twenty-one accessors removed alone from `unaudited_clients`
  (on `da5358f4c8`, and on `724110dfc4` for the four added by this
  version; the test of the clients is the same code in both). The line of
  its client in the first scenario of `cache-safety.t` reads `hits on
  body: 1, rejected for callback: 0`: `call`, `call-results` and
  `statement` for the hooks of Eva; `red`; `status` and `property`;
  `annotations`; `listener`, `register` and `history` for the logger;
  `messages`; `opaque`; `metadata` and `validity` for `Base`; `origin`;
  `daemon`; `location`; `perf`; `safety-result`; `reach-result`;
  `collector-result`; `clear-before` and `clear-after`; `status-state`,
  `status-report` and `status-update`; `cast`; `logic`. On the routes of
  the reviews of the earlier versions: without the accessor of the hooks
  of Eva, `overflow.c` hits and gives `out = 8`; without that of the
  logger, `later.c` hits; without that of the hooks of red statuses,
  `repeat.c` with the client registered after the production hits;
  without that of `Hook.Opaque`, the observer without an audit on
  `alone.c` lets the call hit and is called once during the delivery.
  Without the accessor of the hooks on statuses, `pre-route.c` reads
  `preconditions` in place of `callback`, and without that of `Base`,
  `metadata.c` does: neither reaches a hit any more. The two accessors
  tested in `cache-parts.t`: without `Cache_part.unaudited_clients`, the
  scenarios `unaudited-part` and `inout-client` give `copy: hits 3,
  rejected for callback 0`, and the scenario `verify` gives two hits on
  `checked` and leaves its clauses with `no verification attempted`;
  without `Safety_delivery.unaudited_subscribers`, the subscriber of the
  scenario `stats` registered without an audit lets the three calls hit.
- In `unaudited_status_dependents`: without the test of the hooks on
  update, the line `status-update` hits; with the names of the states of
  Report known whether or not Report is loaded, the line `status-report`
  hits (`724110dfc4`).
- With the action of the server before the clearing of a project
  registered without `audited`, the scenarios of `cache-parts.t` with the
  server loaded lose their hits (`hits: copy 0`) (`724110dfc4`).
- With `Safety_delivery.deliver_write` no longer passing the predicate of
  the write, `prepared.c` reads `registered with the predicate of the
  entry: false` for both alarms: the kernel builds them (`724110dfc4`).
- With the rejection for `preconditions` removed from `admit`: see
  [Preconditions at a hit](#preconditions-at-a-hit).
- With the part of From audited under `-from-verify-assigns`, the
  scenario `verify` gives two hits on `checked`, and the clauses stay
  with `no verification attempted` (`da5358f4c8`).
- With the registry of the audited observers of `Base` also holding each
  function in a list, the test of the registry reads `removed and still
  alive: 128 of 128` (`da5358f4c8`).

Mutations of the earlier versions, not run again on this one; each was
applied alone to the commit named and reverted. With the rejection removed
from `find`, every client of the first scenario lets the call at line 26
hit; `overflow.c` after the lookup hits and gives `out = 8`, where caching
disabled leaves `main` without a state; `interleave.c` hits and calls the
client of red statuses three times, against once. With the check of the
parts evaluating the predicate again instead of using the answers of the
lookup, the scenario `predicate` with the hook registered at the second
evaluation gives one call with `` `Reuse `` and 8 evaluations. With the
installation of the update of the summary no longer one-shot, the scenario
`replace-summary` installs a second function, which runs at the seven
hits. Each flag of the hooks of Eva (call, call results, statement) and of
the logger (`add_listener`, `register`, `on_history_access`), and each
half of `has_add_or_update_hooks`, removed alone, makes the line of its own
client hit. With the hooks of red statuses no longer opaque, the body with
the client of `repeat.c` registered before the production is stored, and
the red client of `collector-effects.t` reads `would-store`. `inside.c`,
`interleave.c`, `second.c`, `pre-route.c` and `later.c` are the programs
of a review of an earlier version, where red clients were admitted and the
categories were compared after the delivery; that review observed the
results quoted above for that version. With the observer of `Hook.Opaque`
of the collector registered without `audited`, the audited observer of
`alone.c` no longer lets its call hit (`hits on body: 0`). With `decide`
evaluating `audited` right after `needed` for each part, in one pass, the
scenario `predicate` with the client of Inout gives `copy: hits 1,
rejected for callback 6` and 10 calls of the client; with the predicates
of the readers evaluated after the audits, the same scenario with
`EVA_TEST_CACHE_PARTS_CARRIER=reader` gives the same. With the count of
the parts registered since the decisions compared with itself in
`Cache_part.unaudited_clients` (the field kept used, as warning 69
requires), the scenario with a registered part gives `copy: hits 3,
rejected for callback 0`. These were applied to the commit now
`dc06f33291` (before the rebase onto #48).

Of the hit scenarios of `cache-safety.t` before the rule of the audited
clients, one rejects since: `overflow.c` with the client of the hooks on
calls. Three tests that counted the calls of a client of the hooks of red
statuses at a hit (`loop.c`, `abort-count.c`, `repeat.c`) run without it:
with it, they reject. The hit scenarios of `collector-effects.t` and of
the `cache_supplied` tests register no client and are unchanged.

The hit scenarios that this version changes: the hand-written entry of
`pre` in `precondition.c`, and that of `metadata.c` with the audited
observer, hit before and are now rejected for `preconditions`; in
`cache-parts.t`, the two calls to `checked` of the scenario `verify` hit
before and now reject their candidates for `callback`. No other hit of the
cram tests of the cache and no oracle of the `cache_supplied` tests
changes with the rules of this entry.

**Open.**

- The list of the steps, the table and the list of audited clients are
  those of the tree at this revision. A change of one of the files of the
  steps that adds a call must be read as the steps were; a new interface
  that a hit or an analysis of the body runs must get a row, and an
  accessor here unless it is argued. Nothing in the build checks this.
- The reading is by hand. The items of *Outside the guarantee* state what
  it does not cover; among them, the operations of the lookup on cvalue
  states were not read for the observers of `Base` and of the origins,
  which the lookup tests in any case.
- The rule of the states that depend on the statuses is by name: a
  plug-in of the tree that adds such a state rejects every candidate while
  it is loaded, until its state is audited and its name added to the
  list. Report is the one known; Metrics has one and already rejects as a
  reader of the statement states.
- A hit evaluates nothing, so the rules of this entry cost the hits on a
  function with a `requires` clause and, under `-from-verify-assigns`,
  every hit while the consumer of the From part is enabled.
- The rejection costs every hit while a client is registered, for instance
  with the log of a plug-in written to a file, while a client of the
  protocol of the server listens to statuses, or while a server runs: its
  daemon of `Async` and its listener of the logger are not audited.
- No regression makes a hit read the metadata of an allocated block or
  create an imprecise value. Both interfaces are tested at the lookup, so
  the question does not change what a hit admits.
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

**Claim.** A hit on a supplied entry evaluates no precondition. The lookup
rejects every candidate of a function whose call checks a `requires`
clause, with the reason `preconditions`, and the body is analysed: its
analysis checks the clauses for the call and emits their statuses, as with
caching disabled. `preconditions` is the last test of a candidate, after
`missing-points` and `nested-delivery`. A memexec hit, which no analysis
with supplied entries has, still evaluates the preconditions and keeps its
states, as before.

**Kind.** OCaml obligation.

**Depends on.**
[A hit runs no client that is not audited](#a-hit-runs-no-client-that-is-not-audited).

**Symbols.** `Supplied_entries.Lookup.admit`,
`Cache_producer.has_preconditions`, `Eva_utils.skip_specifications`,
`Compute_functions.Make.compute_and_cache_call`,
`Transfer_logic.Make.check_fct_preconditions`, `Iterator`,
`Supplied_entries.supply`.

**Argument (source inspection).** An analysed body checks its `requires`
clauses first (`Iterator`, `check_fct_preconditions ~body:true`), when a
behavior of the function has one and its specification is not skipped
(`-eva-skip-stdlib-specs` for a function of the standard library that has a
body). `Cache_producer.has_preconditions` is that condition, read on the
specification of the function at the lookup, and `admit` rejects the
candidate when it holds. The hit branch of `compute_and_cache_call`
therefore checks no clause for a supplied entry: the branch that evaluates
the preconditions is that of memexec. The producer refuses a called
function with `requires` clauses by the same condition (`preconditions`),
so no produced entry is rejected for this reason unless the specification
changed since its production; a hand-written entry of such a function is
rejected at every call.

Before this rule, a hit evaluated the clauses on the input of the call, and
delivered nothing when no state satisfied them. The evaluation ran the
evaluator of terms of Eva and the functions of the kernel that it calls at
a hit, and two reviews each found a client that it ran and that the lookup
had not tested (the observers of `Base` and of the origins). The rule
removes the evaluation from the hit; the clients that only an analysis of
the body runs stay tested at the lookup.

**Evidence (executed).** In `cache-safety.t`, a hand-written entry of `pre`
for x = 1, whose Safety part gives the check `one` a valid status, is a
candidate at the call `pre(1)` at line 18 of `precondition.c`, where g = 0.
The line of the call reads `lookup: rejected (entry 1: preconditions);
execution: analysed`, and `hits on pre: 0`. The precondition `positive` is
reported invalid at line 18 by the analysis of `pre`, its instance at that
call is invalid and has the red context of the call, and no state reaches
the end of `main`. Before the passes at the end of the analysis, `one` is
never tried: the status of the entry is not delivered. The passes then mark
`one` unreachable, and the tables are those of caching disabled. In
`metadata.c`, with the audited observer of the metadata, the entry of `pre`
is rejected for `preconditions` at the second call. The help of the
message category `cache` lists the reason (`help-messages.t`).

Mutation, run alone on `724110dfc4` and reverted: with the rejection
removed from `admit`, the call `pre(1)` hits, `one` is valid before the
passes, and the analysis ends with `out = 5` where the run with caching
disabled leaves `main` without a state and reports `positive` invalid; in
`metadata.c`, the second call hits with the audited observer.

**Open.**

- The rule costs every hit on a function that has a `requires` clause,
  whatever the state of the call. A later ticket can admit such a hit if
  it shows how the statuses of the clauses are obtained without an
  evaluation at the hit, or reads the evaluation to its leaves as this
  entry does for the delivery.
